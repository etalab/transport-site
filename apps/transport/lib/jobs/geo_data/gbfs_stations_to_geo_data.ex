defmodule Transport.Jobs.GBFSStationsToGeoData do
  @moduledoc """
  Job in charge of importing GBFS stations data (docks for bikes usually) to the `geo_data` table.

  It ignores virtual stations and stations with invalid coordinates.
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query

  # The number of workers to run in parallel when fetching GBFS feeds
  @task_concurrency 5
  @task_timeout :timer.seconds(15)

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    Transport.Jobs.BaseGeoData.import_replace_data(:gbfs_stations, &prepare_data_for_insert/1)
  end

  def prepare_data_for_insert(geo_data_import_id) do
    relevant_gbfs_urls()
    |> Task.async_stream(
      fn url -> prepare_stations_data(url, geo_data_import_id) end,
      max_concurrency: @task_concurrency,
      on_timeout: :kill_task,
      timeout: @task_timeout
    )
    |> Stream.filter(fn {status, _} -> status == :ok end)
    |> Stream.map(fn {:ok, value} -> value end)
  end

  def prepare_stations_data(gbfs_url, geo_data_import_id) do
    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- http_client().get(gbfs_url),
         {:ok, json} <- Jason.decode(body),
         {:ok, feed_url} <- {:ok, Transport.GBFSMetadata.feed_url_by_name(json, :station_information)},
         {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- http_client().get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      json["data"]["stations"]
      |> Enum.reject(&(virtual_station?(&1) or missing_coordinates?(&1)))
      |> Enum.map(fn station ->
        %{
          geo_data_import_id: geo_data_import_id,
          geom: %Geo.Point{coordinates: {station["lon"], station["lat"]}, srid: 4326},
          payload: %{
            capacity: station["capacity"],
            name: station_name(station)
          }
        }
      end)
    else
      _ -> []
    end
  end

  defp virtual_station?(%{"is_virtual_station" => true}), do: true
  defp virtual_station?(%{}), do: false

  defp missing_coordinates?(%{"lat" => lat, "lon" => lon}) do
    is_nil(lon) or is_nil(lat)
  end

  defp missing_coordinates?(%{}), do: true

  # From GBFS 1.1 until 2.3
  defp station_name(%{"name" => name}) when is_binary(name), do: name

  # From GBFS 3.0 onwards
  defp station_name(%{"name" => names}) do
    names |> hd() |> Map.get("text")
  end

  @doc """
  Fetches relevant GBFS feeds for which we know they have stations data, based on the metadata we compute.
  Look at the last week of metadata to prevent potential upstream downtimes/
  issues while computing metadata on our side.
  """
  def relevant_gbfs_urls do
    a_week_ago = DateTime.utc_now() |> DateTime.add(-7, :day)

    DB.ResourceMetadata.base_query()
    |> join(:inner, [metadata: m], r in DB.Resource, on: r.id == m.resource_id, as: :resource)
    |> where([resource: r], r.format == "gbfs")
    |> where([metadata: m], m.inserted_at >= ^a_week_ago and fragment("?->'types' \\? 'stations'", m.metadata))
    |> select(
      [resource: r, metadata: m],
      last_value(r.url) |> over(partition_by: m.resource_id, order_by: m.resource_id)
    )
    |> distinct(true)
    |> DB.Repo.all()
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
