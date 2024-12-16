defmodule Transport.Jobs.OutdatedDataNotificationJob do
  use Oban.Worker, max_attempts: 3, tags: ["notifications"]

  @impl Oban.Worker

  def perform(%Oban.Job{id: job_id}) do
    Transport.DataChecker.outdated_data(job_id)
  end
end
