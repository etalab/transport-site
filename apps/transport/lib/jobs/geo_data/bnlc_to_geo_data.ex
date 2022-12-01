defmodule Transport.Jobs.BNLCToGeoData do
  @moduledoc """
  Job in charge of taking the content of the BNLC (Base Nationale de Covoiturage) and storing it
  in the geo_data table
  """
  use Oban.Worker, max_attempts: 3
  import Ecto.Query
  alias NimbleCSV.RFC4180, as: CSV
  require Logger

  @impl Oban.Worker
  def perform(%{}) do
    [%DB.Resource{} = resource] = relevant_dataset() |> DB.Dataset.official_resources()

    Transport.Jobs.BaseGeoData.import_replace_data(resource, &prepare_data_for_insert/2)
    :ok
  end

  def relevant_dataset do
    transport_publisher_label = Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label)

    DB.Dataset
    |> preload(:resources)
    |> where([d], d.type == "carpooling-areas" and d.organization == ^transport_publisher_label)
    |> DB.Repo.one!()
  end

  def prepare_data_for_insert(body, geo_data_import_id) do
    body
    |> CSV.parse_string(skip_headers: false)
    |> Stream.transform([], fn r, acc ->
      if acc == [] do
        {%{}, r}
      else
        {[acc |> Enum.zip(r) |> Enum.into(%{})], acc}
      end
    end)
    |> Stream.map(fn m ->
      %{
        geo_data_import_id: geo_data_import_id,
        geom: %Geo.Point{
          coordinates:
            {m["Xlong"] |> Transport.Jobs.BaseGeoData.parse_coordinate(),
             m["Ylat"] |> Transport.Jobs.BaseGeoData.parse_coordinate()},
          srid: 4326
        },
        payload: m |> Map.drop(["Xlong", "Ylat"])
      }
    end)
  end
end
