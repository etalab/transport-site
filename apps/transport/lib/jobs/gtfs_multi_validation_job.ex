defmodule Transport.Jobs.GTFSValidationJob do
  @moduledoc """
  Multi validation of all GTFS resources
  """
  use Oban.Worker, max_attempts: 3, queue: :resource_validation, tags: ["validation"]

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Transport.Jobs.ResourceHistoryValidationJob.perform(%Oban.Job{
      args: %{"format" => "GTFS", "validator" => Transport.Validators.GTFSTransport}
    })

    :ok
  end
end
