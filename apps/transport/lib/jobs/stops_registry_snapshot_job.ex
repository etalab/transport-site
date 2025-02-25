defmodule Transport.Jobs.StopsRegistrySnapshotJob do
  @moduledoc """
  Job in charge of building a snapshot of the stops registry.
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["registry"], max_attempts: 3
  require Logger
  import Transport.S3.AggregatesUploader

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    with_tmp_file(fn file ->
      :ok = Transport.Registry.Engine.execute(file)

      upload_aggregate!(
        file,
        "stops_registry_#{timestamp()}.csv",
        "stops_registry_latest.csv"
      )
    end)
  end

  defp timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d.%H%M%S.%f")
  end
end
