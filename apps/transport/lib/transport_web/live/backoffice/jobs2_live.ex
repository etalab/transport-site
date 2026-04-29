defmodule TransportWeb.Backoffice.Jobs2Live do
  @moduledoc """
  A quick dashboard for jobs.
  """
  use Gettext, backend: TransportWeb.Gettext
  use Phoenix.LiveView
  use Phoenix.HTML
  import Ecto.Query
  import TransportWeb.Router.Helpers

  @states [:executing, :completed, :scheduled, :retryable, :available, :discarded, :cancelled]

  @max_jobs 100

  # Authentication is assumed to happen in regular HTTP land. Here we verify
  # the user presence + belonging to admin team, or redirect immediately.
  @impl true
  def mount(params, %{"current_user" => current_user} = session, socket) do
    state =
      %{
        locale: Map.get(session, "locale", "fr"),
        states: @states
      }
      |> Map.merge(extract_params(params))

    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()

       socket |> assign(state) |> update_data()
     end)}
  end

  # TO DO: DRY code with proxy live
  # If one calls "redirect" and does not leave immediately, the remaining code will
  # be executed, opening security issues. This method goal is to minimize this risk.
  # See https://hexdocs.pm/phoenix_live_view/security-model.html for overall docs.
  #
  # Also, disconnect will have to be handled:
  # https://hexdocs.pm/phoenix_live_view/security-model.html#disconnecting-all-instances-of-a-given-live-user
  #
  def ensure_admin_auth_or_redirect(socket, current_user, func) do
    socket = assign(socket, current_user: current_user)

    if TransportWeb.Session.admin?(socket) do
      # We track down the current admin so that it can be used by next actions
      # Then call the remaining code, which is expected to return the socket
      func.(socket)
    else
      redirect(socket, to: "/login")
    end
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1000)
  end

  def last_jobs_query(n) do
    from(j in "oban_jobs",
      select: map(j, [:id, :state, :queue, :worker, :args, :inserted_at, :scheduled_at, :errors]),
      order_by: [desc: j.id],
      limit: ^n
    )
  end

  def count_jobs_query do
    from(j in "oban_jobs",
      select: count()
    )
  end

  def filter_worker(query, nil), do: query
  def filter_worker(query, ""), do: query

  def filter_worker(query, worker_filter) do
    reg = "%#{worker_filter}%"
    query |> where([o], ilike(o.worker, ^reg))
  end

  def filter_states(query, []) do
    query |> limit(0)
  end

  def filter_states(query, states) do
    query |> where([o], o.state in ^states)
  end

  def jobs_count(condition) do
    query =
      from(j in "oban_jobs",
        select: %{
          worker: j.worker,
          truncated_date_time: fragment("date_trunc('hour', ?) as truncated_date_time", j.inserted_at),
          count: count()
        },
        group_by: [:worker, fragment("truncated_date_time")],
        order_by: [desc: fragment("truncated_date_time"), asc: :worker]
      )

    query
    |> apply_condition(condition)
    |> oban_query()
    |> Enum.group_by(fn d -> Shared.DateTimeDisplay.convert_to_paris_time(d.truncated_date_time) end)
    |> Enum.sort(:desc)
  end

  def oban_query(query), do: Oban.config() |> Oban.Repo.all(query)

  def last_jobs(n, condition), do: last_jobs_query(n) |> apply_condition(condition) |> oban_query

  def count_jobs(condition), do: count_jobs_query() |> apply_condition(condition) |> oban_query |> Enum.at(0)

  defp apply_condition(query, {worker, active_states}) do
    query
    |> filter_worker(worker)
    |> filter_states(active_states)
  end

  defp update_data(socket) do
    locale = socket.assigns |> Map.get(:locale, "fr")

    condition = {socket.assigns[:worker], socket.assigns |> active_states()}

    assign(socket,
      last_updated_at: DateTime.utc_now() |> format_datetime(locale),
      jobs: last_jobs(@max_jobs, condition),
      count_jobs: count_jobs(condition),
      jobs_count: jobs_count(condition)
    )
  end

  defp active_states(assigns) do
    @states
    |> Enum.filter(fn state -> assigns[state] end)
    |> Enum.map(&to_string/1)
  end

  defp format_datetime(dt, locale) do
    dt
    |> Shared.DateTimeDisplay.format_datetime_to_paris(locale, no_timezone: true, with_seconds: true)
  end

  @impl true
  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    update = extract_params(params)

    socket = socket |> assign(update)

    {:noreply, update_data(socket)}
  end

  @impl true
  def handle_event("filter", params, socket) do
    update = extract_params(params) |> drop_defaults()

    socket =
      socket
      |> push_patch(to: backoffice_live_path(socket, TransportWeb.Backoffice.Jobs2Live, update))

    {:noreply, socket}
  end

  def format_1_hour_range(from) do
    to = DateTime.add(from, 1, :hour)

    days_diff = from |> DateTime.to_date() |> Date.diff(Date.utc_today())

    date =
      case days_diff do
        0 -> "Today"
        -1 -> "Yesterday"
        1 -> "Tomorrow"
        _ -> Shared.DateTimeDisplay.format_date(from, "en")
      end

    "#{date} between #{format_time(from)} and #{format_time(to)}"
  end

  defp format_time(dt) do
    Shared.DateTimeDisplay.format_time_to_paris(dt, "en", no_timezone: true)
  end

  defp extract_params(params) do
    flags = flags(params, [:listing | @states])

    %{
      worker: Map.get(params, "worker", nil)
    }
    |> Map.merge(flags)
  end

  defp flags(params, keys) do
    keys
    |> Enum.map(fn key ->
      {key, flag(params, to_string(key))}
    end)
    |> Map.new()
  end

  defp flag(params, key) do
    case Map.get(params, key) do
      "true" -> true
      "false" -> false
      _ -> true
    end
  end

  defp drop_defaults(updates) do
    Map.reject(updates, fn {_key, value} ->
      value == true or value == ""
    end)

  end
end
