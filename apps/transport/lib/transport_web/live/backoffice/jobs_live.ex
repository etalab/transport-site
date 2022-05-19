defmodule TransportWeb.Backoffice.JobsLive do
  @moduledoc """
  A quick dashboard for jobs.
  """
  use Phoenix.LiveView
  use Phoenix.HTML
  import Ecto.Query
  import TransportWeb.Router.Helpers

  # Authentication is assumed to happen in regular HTTP land. Here we verify
  # the user presence + belonging to admin team, or redirect immediately.
  @impl true
  def mount(params, session, socket) do
    %{
      "current_user" => current_user
    } = session

    worker = params |> Map.get("worker", nil)

    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()

       socket
       |> assign(%{search_worker: :search_worker})
       |> assign(%{worker: worker})
       |> update_data()
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
    if current_user && TransportWeb.Router.is_transport_data_gouv_member?(current_user) do
      # We track down the current admin so that it can be used by next actions
      socket = assign(socket, current_admin_user: current_user)
      # Then call the remaining code, which is expected to return the socket
      func.(socket)
    else
      redirect(socket, to: "/login")
    end
  end

  defp schedule_next_update_data do
    Process.send_after(self(), :update_data, 1000)
  end

  def last_jobs_query(state, n) do
    from(j in "oban_jobs",
      select: map(j, [:id, :state, :queue, :worker, :args, :inserted_at, :errors]),
      order_by: [desc: j.id],
      where: j.state == ^state,
      limit: ^n
    )
  end

  def count_jobs_query(state) do
    from(j in "oban_jobs",
      select: count(),
      where: j.state == ^state
    )
  end

  def filter_worker(query, nil), do: query
  def filter_worker(query, ""), do: query

  def filter_worker(query, worker_filter) do
    reg = "%#{worker_filter}%"
    query |> where([o], ilike(o.worker, ^reg))
  end

  def jobs_count(worker) do
    query =
      from(j in "oban_jobs",
        select: %{worker: j.worker, hour: fragment("date_trunc('hour', ?) as hour", j.inserted_at), count: count()},
        group_by: [:worker, fragment("hour")],
        order_by: [desc: fragment("hour"), asc: :worker]
      )

    query
    |> filter_worker(worker)
    |> oban_query()
    |> Enum.group_by(fn d -> Calendar.strftime(d.hour, "%Y-%m-%d %Hh") end)
    |> Enum.sort(:desc)
  end

  def oban_query(query), do: Oban.config() |> Oban.Repo.all(query)

  def last_jobs(state, n, worker), do: state |> last_jobs_query(n) |> filter_worker(worker) |> oban_query

  def count_jobs(state, worker), do: state |> count_jobs_query |> filter_worker(worker) |> oban_query |> Enum.at(0)

  defp update_data(socket, worker_filter \\ nil) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      executing_jobs: last_jobs("executing", 5, worker_filter),
      count_executing_jobs: count_jobs("executing", worker_filter),
      last_completed_jobs: last_jobs("completed", 5, worker_filter),
      count_completed_jobs: count_jobs("completed", worker_filter),
      available_jobs: last_jobs("available", 5, worker_filter),
      count_available_jobs: count_jobs("available", worker_filter),
      last_discarded_jobs: last_jobs("discarded", 5, worker_filter),
      count_discarded_jobs: count_jobs("discarded", worker_filter),
      jobs_count: jobs_count(worker_filter)
    )
  end

  @impl true
  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket, socket.assigns |> Map.get(:worker))}
  end

  @impl true
  def handle_params(%{"worker" => worker}, _uri, socket) do
    socket = socket |> assign(%{worker: worker})

    {:noreply, update_data(socket, worker)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, update_data(socket)}
  end

  @impl true
  def handle_event("filter", %{"search_worker" => %{"worker" => worker}}, socket) do
    socket =
      socket
      |> push_patch(
        to: backoffice_live_path(socket, TransportWeb.Backoffice.JobsLive, worker: worker)
      )

    {:noreply, socket}
  end

  def build_session(conn) do
    %{
      "current_user" => conn.assigns[:current_user]
    }
  end
end
