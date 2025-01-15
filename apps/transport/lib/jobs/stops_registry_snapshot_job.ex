defmodule Transport.Jobs.StopsRegistrySnapshotJob do
  @moduledoc """
  Job in charge of building a snapshot of the stops registry.
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["registry"], max_attempts: 3
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    file = "#{System.tmp_dir!()}/registre-arrets.csv"

    :ok = Transport.Registry.Engine.execute(file)

    file
    |> compress()
    |> upload("stops_registry_#{timestamp()}.csv.zip")
    |> link("stops_registry_latest.csv.zip")
  end

  defp timestamp do
    DateTime.utc_now()
    |> Calendar.strftime("%Y%m%d.%H%M%S.%f")
  end

  defp compress(file) do
    archive = "#{file}.zip"

    {:ok, _filename} =
      :zip.create(
        archive,
        [String.to_charlist(file)]
      )

    archive
  end

  defp upload(file, filename) do
    Transport.S3.stream_to_s3!(:stops_registry, file, filename)
  end

  defp link(s3_path, filename) do
    Transport.S3.remote_copy_file(:stops_registry, s3_path, filename)
  end
end
