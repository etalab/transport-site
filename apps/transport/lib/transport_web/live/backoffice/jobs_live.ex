defmodule TransportWeb.Backoffice.JobsLive do
  @moduledoc """
  A quick dashboard for jobs.
  """
  use Phoenix.LiveView
  import Ecto.Query

  # Authentication is assumed to happen in regular HTTP land. Here we verify
  # the user presence + belonging to admin team, or redirect immediately.
  def mount(_params, session, socket) do
    %{
      "current_user" => current_user
    } = session

    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       if connected?(socket), do: schedule_next_update_data()

       socket |> update_data()
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

  def jobs_count do
    query =
      from(j in "oban_jobs",
        select: %{worker: j.worker, hour: fragment("date_trunc('hour', ?) as hour", j.inserted_at), count: count()},
        group_by: [:worker, fragment("hour")],
        order_by: [desc: fragment("hour"), asc: :worker]
      )

    query |> oban_query() |> Enum.group_by(fn d -> Calendar.strftime(d.hour, "%Y-%m-%d %Hh") end) |> Enum.sort(:desc)
  end

  def oban_query(query), do: Oban.config() |> Oban.Repo.all(query)

  def last_jobs(state, n), do: state |> last_jobs_query(n) |> oban_query

  def count_jobs(state), do: state |> count_jobs_query |> oban_query |> Enum.at(0)

  defp update_data(socket) do
    assign(socket,
      last_updated_at: (Time.utc_now() |> Time.truncate(:second) |> to_string()) <> " UTC",
      executing_jobs: last_jobs("executing", 5),
      count_executing_jobs: count_jobs("executing"),
      last_completed_jobs: last_jobs("completed", 5),
      count_completed_jobs: count_jobs("completed"),
      available_jobs: last_jobs("available", 5),
      count_available_jobs: count_jobs("available"),
      last_discarded_jobs: last_jobs("discarded", 5),
      count_discarded_jobs: count_jobs("discarded"),
      jobs_count: jobs_count()
    )
  end

  def handle_info(:update_data, socket) do
    schedule_next_update_data()
    {:noreply, update_data(socket)}
  end

  def build_session(conn) do
    %{
      "current_user" => conn.assigns[:current_user]
    }
  end
end
