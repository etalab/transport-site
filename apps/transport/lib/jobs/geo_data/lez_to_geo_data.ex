defmodule Transport.Jobs.LowEmissionZonesToGeoData do
  @moduledoc """
  Job in charge of taking the areas of the national low emission zones (ZFE)
  and storing the result in the `geo_data` table.
  """
  use Oban.Worker, max_attempts: 3

  @impl Oban.Worker
  def perform(%{}) do
    Transport.ConsolidatedDataset.resource(:zfe)
    |> Transport.Jobs.BaseGeoData.import_replace_data(&prepare_data_for_insert/2)

    :ok
  end

  def prepare_data_for_insert(body, geo_data_import_id) do
    body
    |> Jason.decode!()
    |> Map.fetch!("features")
    |> Enum.filter(&filter_dates/1)
    |> Enum.map(fn %{"geometry" => geometry, "properties" => properties} ->
      {:ok, geom} = Geo.JSON.decode(geometry)

      %{
        geo_data_import_id: geo_data_import_id,
        geom: %{geom | srid: 4326},
        payload: properties
      }
    end)
  end

  @doc """
  Keep only records when the area is currently in force according to dates.

  iex> filter_dates(%{"properties" => %{"date_debut" => "2000-01-01", "date_fin" => "2050-01-01"}})
  true
  iex> filter_dates(%{"properties" => %{"date_debut" => "1970-01-01", "date_fin" => "1970-02-01"}})
  false
  iex> filter_dates(%{"properties" => %{"date_debut" => "1970-01-01", "date_fin" => nil}})
  true
  iex> filter_dates(%{"properties" => %{"date_debut" => "2200-01-01", "date_fin" => nil}})
  false
  iex> filter_dates(%{"properties" => %{"date_debut" => "2200-01-01"}})
  false
  iex> filter_dates(%{"properties" => %{}})
  true
  """
  def filter_dates(%{"properties" => properties}) do
    case properties do
      %{"date_debut" => date_debut, "date_fin" => date_fin}
      when not is_nil(date_debut) and date_fin not in [nil, "null"] ->
        date_range = Date.range(Date.from_iso8601!(date_debut), Date.from_iso8601!(date_fin))
        Date.utc_today() in date_range

      %{"date_debut" => date_debut} ->
        Date.compare(Date.utc_today(), Date.from_iso8601!(date_debut)) == :gt

      _ ->
        true
    end
  end
end
