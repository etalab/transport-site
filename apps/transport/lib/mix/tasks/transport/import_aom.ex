defmodule Mix.Tasks.Transport.ImportAom do
  @moduledoc """
  Import the AOM files and updates the database

  The aom files are custom made from an excel file from the Cerema
  https://www.data.gouv.fr/fr/datasets/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/

  and pushed as community ressource on data.gouv.
  There are 2 files:
  - one with the description of each aom
  - one with the list of cities that are part of each aom

  This is a one shot import task, run when the aom have changed.

  To run this script:
  connect to the server, then run it as a mix task:
  `mix Transport.ImportAom`

  or run it in iex:
  `iex -S mix`
  then
  `Mix.Tasks.Transport.ImportAom.run([])`
  """

  use Mix.Task
  import Ecto.{Query}
  alias DB.{AOM, Region, Repo}
  require Logger

  @aom_file "https://static.data.gouv.fr/resources/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/20201112-141547/base-aom-2020.csv"
  @aom_insee_file "https://static.data.gouv.fr/resources/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/20201112-142236/aom-insee.csv"

  @spec to_int(binary()) :: number() | nil
  def to_int(""), do: nil
  def to_int("#N/D"), do: nil

  def to_int(str) do
    str
    |> String.replace(" ", "")
    # also replace non breaking spaces
    |> String.replace("\u00A0", "")
    |> String.to_integer()
  end

  @spec changeset(AOM.t(), map()) :: {integer(), Ecto.Changeset.t()}
  def changeset(aom, line) do
    # some names have been manually set, we want to keep them
    insee =
      case aom.insee_commune_principale do
        nil -> line["Code INSEE Commune Principale"]
        n -> n
      end

    nom = line["Nom de l’AOM pour transport.data.gouv.fr"]

    new_region = Repo.get_by(Region, nom: normalize_region(line["Régions"]))

    if !is_nil(aom.region) and !is_nil(new_region) and aom.region != new_region do
      Logger.info("aom #{nom} || previous region #{aom.region.nom} --- #{new_region.nom}")
    end

    external_id = to_int(line["Id réseau"])

    {external_id,
     Ecto.Changeset.change(aom, %{
       composition_res_id: external_id,
       insee_commune_principale: insee,
       departement: line["Dep"],
       siren: line["N° SIREN"],
       nom: nom,
       forme_juridique: normalize_forme(line["Forme juridique"]),
       nombre_communes: to_int(line["Nombre de communes du RT"]),
       population_muni_2014: to_int(line["Population municipale 2017"]),
       population_totale_2014: to_int(line["Population totale calculée"]),
       surface: line["Surface (km²)"],
       commentaire: line["Commentaire"],
       region: new_region
     })}
  end

  @spec normalize_region(binary()) :: binary()
  defp normalize_region("Grand-Est"), do: "Grand Est"
  defp normalize_region("Provence-Alpes-Côte-d'Azur"), do: "Région Sud — Provence-Alpes-Côte d’Azur"
  defp normalize_region("Provence-Alpes-Côte d'Azur"), do: "Région Sud — Provence-Alpes-Côte d’Azur"
  defp normalize_region("Nouvelle Aquitaine"), do: "Nouvelle-Aquitaine"
  defp normalize_region("Auvergne-Rhône Alpes"), do: "Auvergne-Rhône-Alpes"
  defp normalize_region(region), do: region

  @spec normalize_forme(binary()) :: binary()
  defp normalize_forme("CA"), do: "Communauté d'agglomération"
  defp normalize_forme("CU"), do: "Communauté urbaine"
  defp normalize_forme("CC"), do: "Communauté de communes"
  defp normalize_forme("SIVU"), do: "Syndicat intercommunal à vocation unique"
  defp normalize_forme("METRO"), do: "Métropole"
  defp normalize_forme("SMF"), do: "Syndicat mixte fermé"
  defp normalize_forme("SMO"), do: "Syndicat mixte ouvert"
  defp normalize_forme("EPA"), do: "Établissement public administratif"
  defp normalize_forme("EPL"), do: "Établissement public local"
  defp normalize_forme(f), do: f

  @shortdoc "One shot update of AOM from a data.gouv.fr community ressource file"
  def run(_) do
    Mix.Task.run("app.start")

    aoms =
      AOM
      |> Repo.all()
      |> Enum.map(fn aom -> {aom.composition_res_id, aom} end)
      |> Map.new()

    # some external ids have changed, we manually update them
    update_modified_ids()

    # get all the aom to import, outside of the transaction to reduce the time in the transaction
    aom_to_add = get_aom_to_import()

    Repo.transaction(
      fn ->
        # we load all aoms
        import_aoms(aom_to_add)

        delete_old_aoms(aom_to_add, aoms)
        # we load the join on cities
        import_insee_aom()
        # we can then compute the aom geometries (the union of each cities geometries)
        compute_geom()
      end,
      # computing the geometries can be a bit long, we set a big timeout
      timeout: 600_000
    )
  end

  defp get_aom_to_import do
    Logger.info("importing aoms")

    {:ok, %HTTPoison.Response{status_code: 200, body: body}} =
      HTTPoison.get(@aom_file, [], hackney: [follow_redirect: true])

    {:ok, stream} = StringIO.open(body)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(separator: ?,, headers: true)
    |> Enum.reject(fn {:ok, line} -> is_nil(line["Id réseau"]) end)
    |> Enum.reject(fn {:ok, line} -> line["Id réseau"] == "" end)
    |> Enum.map(fn {:ok, line} ->
      AOM
      |> Repo.get_by(composition_res_id: to_int(line["Id réseau"]))
      |> case do
        nil ->
          %AOM{}

        aom ->
          aom
      end
      |> Repo.preload(:region)
      |> changeset(line)
    end)
    |> MapSet.new()
  end

  defp import_aoms(aom_to_add) do
    aom_to_add
    |> Enum.each(fn {_id, aom} -> Repo.insert_or_update!(aom) end)
  end

  defp delete_old_aoms(aom_added, old_aoms) do
    Logger.info("deleting removed aom")

    composition_res_id_added =
      aom_added
      |> Enum.map(fn {id, _changeset} -> id end)
      |> MapSet.new()

    old_aoms
    |> Enum.each(fn {composition_res_id, old_aom} ->
      unless MapSet.member?(composition_res_id_added, composition_res_id) do
        Logger.info("trying to delete old aom: #{old_aom.id} - #{old_aom.nom}")

        # Note: if the delete is impossible, you need to find what still depend on this aom,
        # and change the link to a newer aom
        Repo.delete!(old_aom)
      end
    end)
  end

  defp import_insee_aom do
    Logger.info("Linking aoms to cities")

    {:ok, %HTTPoison.Response{status_code: 200, body: body}} =
      HTTPoison.get(@aom_insee_file, [], hackney: [follow_redirect: true])

    {:ok, stream} = StringIO.open(body)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(separator: ?,, headers: true)
    |> Enum.reject(fn {:ok, line} -> {line["aom"], line["insee"]} end)
    |> Enum.reject(fn {:ok, {aom, insee}} -> aom == "" || insee == "" end)
    |> Enum.each(fn {:ok, {aom, insee}} ->
      Commune
      |> where([c], c.insee == ^insee)
      |> Repo.update_all(set: [aom_res_id: String.to_integer(aom)])
    end)
  end

  defp compute_geom do
    Logger.info("computing aom geometries")

    Repo.update_all(
      from(a in AOM,
        update: [
          set: [
            geom:
              fragment(
                """
                  (
                    SELECT
                    ST_UNION(commune.geom)
                    FROM commune
                    WHERE commune.aom_res_id = ?
                  )
                """,
                a.composition_res_id
              )
          ]
        ]
      ),
      []
    )
  end

  defp update_modified_ids do
    Logger.info("updating modified external ids")
    # The AOM redon has seen its id changed, so we update it before hand
    # (if that has not been already done)
    redon =
      AOM
      |> where([a], a.composition_res_id == 462 and a.nom == "Redon Agglomération")
      |> Repo.one()

    unless is_nil(redon) do
      redon
      |> Ecto.Changeset.change(%{composition_res_id: 470})
      |> Repo.update!()
    end
  end
end
