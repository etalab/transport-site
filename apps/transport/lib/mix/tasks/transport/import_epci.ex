defmodule Mix.Tasks.Transport.ImportEPCI do
  @moduledoc """
  Import the EPCI file to get the relation between the cities and the EPCI
  Run: mix transport.importEPCI
  """

  use Mix.Task
  import Ecto.Query
  alias Ecto.Changeset
  alias DB.{Commune, EPCI, Repo}
  require Logger

  @epci_file "https://unpkg.com/@etalab/decoupage-administratif@4.0.0/data/epci.json"
  @epci_geojson_url "http://etalab-datasets.geo.data.gouv.fr/contours-administratifs/2024/geojson/epci-100m.geojson"

  def run(_params) do
    Logger.info("Importing EPCIs")

    Mix.Task.run("app.start")

    %{status: 200, body: json} = Req.get!(@epci_file, connect_options: [timeout: 15_000], receive_timeout: 15_000)
    check_communes_list(json)
    geojsons = geojson_by_insee()

    json |> Enum.each(&insert_epci(&1, geojsons))
    json |> Enum.each(&update_communes_epci/1)

    # Remove EPCIs that have been removed
    epci_codes = json |> Enum.map(& &1["code"])
    EPCI |> where([e], e.insee not in ^epci_codes) |> Repo.delete_all()

    nb_epci = Repo.aggregate(EPCI, :count, :id)
    Logger.info("#{nb_epci} are now in database")
    Logger.info("Ensure valid geometries and rectify if needed.")
    ensure_valid_geometries()
    :ok
  end

  @spec get_or_create_epci(binary()) :: EPCI.t()
  defp get_or_create_epci(code) do
    EPCI
    |> Repo.get_by(insee: code)
    |> case do
      nil ->
        %EPCI{}

      epci ->
        epci
    end
  end

  @spec insert_epci(map(), map()) :: any()
  defp insert_epci(%{"code" => code, "nom" => nom, "type" => type, "modeFinancement" => mode_financement}, geojsons) do
    code
    |> get_or_create_epci()
    |> EPCI.changeset(%{
      insee: code,
      nom: nom,
      type: normalize_type(type),
      mode_financement: normalize_mode_financement(mode_financement),
      geom: build_geometry(geojsons, code)
    })
    |> Repo.insert_or_update()
  end

  defp check_communes_list(body) do
    all_communes =
      body
      |> Enum.map(fn epci ->
        epci["membres"] |> Enum.map(& &1["code"])
      end)
      |> List.flatten()

    duplicate_communes = all_communes -- Enum.uniq(all_communes)

    if duplicate_communes != [] do
      raise "One or multiple communes belong to different EPCIs. List: #{duplicate_communes}"
    end
  end

  defp update_communes_epci(%{"code" => code, "membres" => m}) do
    communes_arr = get_insees(m)
    communes = Repo.all(from(c in Commune, where: c.insee in ^communes_arr))

    communes
    |> Enum.each(fn commune ->
      commune
      |> Changeset.change(epci_insee: code)
      |> Repo.update()
    end)

    :ok
  end

  @spec get_insees([map()]) :: [binary()]
  defp get_insees(members) do
    members
    |> Enum.map(fn m -> m["code"] end)
  end

  defp geojson_by_insee do
    %{status: 200, body: body} =
      Req.get!(@epci_geojson_url, connect_options: [timeout: 15_000], receive_timeout: 15_000)

    body
    # Req doesn’t decode GeoJSON body automatically as it does for JSON
    |> Jason.decode!()
    |> Map.fetch!("features")
    |> Map.new(fn record -> {record["properties"]["code"], record["geometry"]} end)
  end

  defp build_geometry(geojsons, insee) do
    {:ok, geom} = Geo.PostGIS.Geometry.cast(Map.fetch!(geojsons, insee))
    %{geom | srid: 4326}
  end

  defp ensure_valid_geometries,
    do: Repo.query!("UPDATE epci SET geom = ST_MakeValid(geom) WHERE NOT ST_IsValid(geom);")

  @spec normalize_type(binary()) :: binary()
  defp normalize_type("CA"), do: "Communauté d'agglomération"
  defp normalize_type("CU"), do: "Communauté urbaine"
  defp normalize_type("CC"), do: "Communauté de communes"
  defp normalize_type("METRO"), do: "Métropole"
  defp normalize_type("MET69"), do: "Métropole de Lyon"

  @spec normalize_mode_financement(binary()) :: binary()
  defp normalize_mode_financement("FPU"), do: "Fiscalité professionnelle unique"
  defp normalize_mode_financement("FA"), do: "Fiscalité additionnelle"
end
