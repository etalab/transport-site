require Logger
import Ecto.Query

folder = Path.join([__DIR__, "geojson"])
unless File.exists?(folder), do: File.mkdir_p!(folder)

Transport.GTFSExportStops.data_import_ids()
# |> Enum.take(100)
# |> Enum.drop(99)
|> Enum.each(fn id ->
  file = Path.join(folder, "data-import-#{id}.geojson")

  unless File.exists?(file) do
    stops =
      DB.GTFS.Stops
      |> where([s], s.data_import_id == ^id)
      |> order_by([s], [s.data_import_id, s.id])
      |> select([s], %{
        d_id: s.data_import_id,
        stop_id: s.stop_id,
        stop_name: s.stop_name,
        stop_lat: s.stop_lat,
        stop_lon: s.stop_lon,
        stop_location_type: s.location_type
      })
      |> DB.Repo.all()

    geojson =
      %{
        type: "FeatureCollection",
        features:
          stops
          |> Enum.map(fn s ->
            %{
              type: "Feature",
              geometry: %{
                type: "Point",
                coordinates: [Map.fetch!(s, :stop_lon), Map.fetch!(s, :stop_lat)]
              },
              properties: %{
                d_id: Map.fetch!(s, :d_id),
                stop_id: Map.fetch!(s, :stop_id),
                stop_location_type: Map.fetch!(s, :stop_location_type)
              }
            }
          end)
      }
      |> Jason.encode!()

    Logger.info("Generating #{file}")
    File.write!(file, geojson)
  end
end)
