defmodule Transport.Jobs.AnalyzeIRVEJob do
  @moduledoc """
  An Oban wrapper for the IRVE mass-scan & analyze job.

  This wrapper ensures only a single instance can be enqueued and executed at once.

  Data Gouv is queried for all static IRVE resources, then each resource is fetched via HTTP to estimate the
  number of charging points, and a report is saved into the database.

  Progress is broadcasted to the "outside world" (other parts of the app) via gossip using a specific `:type` marker.
  """

  use Oban.Worker, max_attempts: 1, unique: [period: 3600, states: [:available, :scheduled, :executing]]
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{id: job_id}) do
    start_async_work()
    wait_for_work_completion(job_id)

    :ok
  end

  def start_async_work do
    job_pid = self()

    # NOTE: a call to `Task.async` normally requires a `Task.await` to ensure we monitor completion.
    # In the current implementation though, we use (see `wait_for_work_completion`) which plays that role.
    # See https://hexdocs.pm/oban/reporting-progress.html for inspiration.
    Task.async(fn ->
      try do
        Logger.info("IRVE: starting global analyse...")
        send(job_pid, {:progress, 0})
        resources = Transport.IRVE.Extractor.datagouv_resources() |> Enum.into([])

        count = resources |> length()
        Logger.info("IRVE: processing #{count} resources...")
        cb = fn index -> send(job_pid, {:progress, (100.0 * index / count) |> trunc()}) end
        resources = Transport.IRVE.Extractor.download_and_parse_all(resources, cb)

        Logger.info("IRVE: saving report...")
        Transport.IRVE.Extractor.insert_report!(resources)

        send(job_pid, :complete)
      rescue
        error ->
          Logger.error("IRVE:" <> Exception.format(:error, error, __STACKTRACE__))
          send(job_pid, :failed)
      end
    end)
  end

  def notify(job_id, status, progress \\ nil) do
    Oban.Notifier.notify(Oban, :gossip, %{
      "type" => "analyze_irve",
      "job_id" => job_id,
      "status" => status,
      "progress" => progress
    })
  end

  # recursive loop replacing `Task.await` (but we'd need to better handle errors here)
  def wait_for_work_completion(job_id) do
    receive do
      {:progress, percent} ->
        notify(job_id, :progress, percent)
        wait_for_work_completion(job_id)

      :complete ->
        notify(job_id, :complete)

      :failed ->
        notify(job_id, :failed)
    after
      30_000 ->
        notify(job_id, :failed)
        raise RuntimeError, "look's like we're a bit stuck!"
    end
  end
end
