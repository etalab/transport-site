defmodule Transport.Jobs.GTFSValidationJob do
  @moduledoc """
  Multi validation of all GTFS resources
  """
  use Oban.Worker, max_attempts: 3, queue: :resource_validation, tags: ["validation"]

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    force_validation = args |> Map.get("force_validation", false)
    only_latest_resource_history = args |> Map.get("only_latest_resource_history", false)

    Transport.Jobs.ResourceHistoryValidationJob.perform(%Oban.Job{
      args: %{
        "format" => "GTFS",
        "validator" => Transport.Validators.GTFSTransport |> to_string(),
        "force_validation" => force_validation,
        "only_latest_resource_history" => only_latest_resource_history
      }
    })
  end
end
