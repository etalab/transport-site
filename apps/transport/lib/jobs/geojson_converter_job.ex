defmodule Transport.GeojsonConverterJob do
  @moduledoc """
  Job converting a GTFS file to GeoJSON
  """
  use Oban.Worker, max_attempts: 1
  import Logger
  alias DB.{Repo, Resource}

  # TO DO: handle the case where a resource cannot be found

  @impl true
  def perform(%{id: id, args: %{"resource_id" => resource_id}}) do
    Logger.info("Job #{id} started by #{__MODULE__}")

    url = Resource |> Repo.get!(resource_id) |> Map.fetch!(:url)

    # TO DO how is the tmp folder cleaned (upon completion or after a crash)?
    file_path = System.tmp_dir!() |> Path.join("#{id}_download")

    # TO DO stream file to disk
    # TO DO verify headers (content-type) and maybe provide alerts to providers!
    %{status: 200, body: body} = Unlock.HTTP.Client.impl().get!(url, [])
    File.write!(file_path, body)

    # TO DO add a bit of logging

    {:ok, output} = file_path |> Transport.GtfsToGeojsonConverter.convert()

    output_path =
      System.tmp_dir!()
      |> Path.join("#{id}_output.geojson")

    File.write!(output_path, output)

    Logger.info("Job #{id} success, saving result: #{output_path}")

    :ok
  end
end

defmodule Transport.GtfsToGeojsonConverter do
  @moduledoc """
    Given a GTFS file path, create from the file the corresponding geojson with the stops and line shapes if available.
  """
  @spec convert(binary()) :: {:ok, binary()} | {:error, any()}
  def convert(file_path) do
    binary_path = Path.join(Application.fetch_env!(:transport, :transport_tools_folder), "gtfs-geojson")
    Transport.RamboLauncher.run(binary_path, ["--input", file_path])
  end
end
