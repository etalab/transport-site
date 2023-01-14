defmodule TransportWeb.Backoffice.DataImportBatchReportLive do
  use Phoenix.LiveView
  use Phoenix.HTML
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import Ecto.Query
  import TransportWeb.Router.Helpers

  @impl true
  def mount(_params, %{"current_user" => current_user} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       socket
       |> assign_data()
       |> assign(job_running: false)
     end)}
  end

  def assign_data(socket) do
    record = DB.Repo.one(from(x in DB.DataImportBatch, order_by: [desc: x.id], limit: 1))

    if record do
      result = record.summary["result"]

      socket
      |> assign(
        result: sort(result),
        stats: compute_stats(result),
        last_updated_at: (record.inserted_at |> to_string()) <> " UTC"
      )
    else
      socket
      |> assign(
        result: [],
        stats: nil,
        last_updated_at: nil
      )
    end
  end

  @doc """
  Provide a default sort helping us group errors by similarity
  """
  def sort(result) do
    Enum.sort_by(result, fn item ->
      [item["status"], item["error_struct"], item["error_message"]]
    end)
  end

  @doc """
  Provide a bit of stats to display a summary
  """
  def compute_stats(result) do
    result
    |> Enum.group_by(fn x -> x["status"] end)
    |> Enum.map_join(", ", fn {k, v} -> "#{k} : #{Enum.count(v)}" end)
  end

  @impl true
  def handle_event("refresh", _, socket) do
    send(self(), :enqueue_job)
    {:noreply, socket |> assign(:job_running, true)}
  end

  @impl true
  def handle_info(:enqueue_job, socket) do
    :ok = Oban.Notifier.listen([:gossip])

    %{id: job_id} =
      %{}
      |> Transport.Jobs.GTFSImportStopsJob.new()
      |> Oban.insert!()

    socket =
      receive do
        {:notification, :gossip, %{"complete" => ^job_id}} ->
          socket
          |> assign(:job_running, false)
          |> assign_data()
      end

    Oban.Notifier.unlisten([:gossip])
    {:noreply, socket}
  end

  # catch-all
  def handle_info(_, socket) do
    {:noreply, socket}
  end
end
