defmodule Transport.ImportAOMs do
  @moduledoc """
  Import the AOM files and updates the database.

  The AOM files are custom made from an Excel file from the Cerema
  https://www.data.gouv.fr/fr/datasets/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/
  https://www.cerema.fr/fr/actualites/liste-composition-autorites-organisatrices-mobilite-au-1er-4

  and pushed as community resources on data.gouv.fr.
  There are 2 files:
  - one with the description of each AOM
  - one with the list of cities that are part of each AOM

  This is a one shot import task, run when the AOM have changed, at least every year.

  The import can be launched from the site backoffice.
  """

  import Ecto.{Query}
  alias DB.{AOM, Commune, Region, Repo}
  require Logger

  # The 2 community resources stable urls
  @aom_file "https://gist.githubusercontent.com/AntoineAugusti/8daac155f4d12b32ccd4e0a75bb964c7/raw/aoms.csv"
  @aom_insee_file "https://gist.githubusercontent.com/AntoineAugusti/8daac155f4d12b32ccd4e0a75bb964c7/raw/aoms_insee.csv"

  @spec to_int(binary()) :: number() | nil
  def to_int(""), do: nil
  def to_int("#N/D"), do: nil
  def to_int("#ERROR!"), do: nil

  def to_int(str) do
    str
    |> String.replace(" ", "")
    # also replace non breaking spaces
    |> String.replace("\u00A0", "")
    |> String.to_integer()
  end

  @spec changeset(AOM.t(), map()) :: {integer(), Ecto.Changeset.t()}
  def changeset(aom, line) do
    insee =
      (Repo.get_by(Commune, siren: line["N°SIREN Commune principale"]) ||
         Repo.get_by(Commune, insee: line["N°SIREN Commune principale"])).insee

    nom = String.trim(line["Nom de l’AOM"])

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
       population_muni_2014: to_int(line["Population municipale 2018"]),
       population_totale_2014: to_int(line["Population totale 2018"]),
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
  defp normalize_region("Nouvelle Calédonie"), do: "Nouvelle-Calédonie"
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
  defp normalize_forme("PETR"), do: "Pôle d'équilibre territorial et rural"
  defp normalize_forme(f), do: f

  def run do
    aoms =
      AOM
      |> Repo.all()
      |> Enum.map(fn aom -> {aom.composition_res_id, aom} end)
      |> Map.new()

    # get all the aom to import, outside of the transaction to reduce the time in the transaction
    aom_to_add = get_aom_to_import()

    {:ok, _} =
      Repo.transaction(
        fn ->
          disable_trigger()
          # we load all aoms
          import_aoms(aom_to_add)

          migrate_aoms()
          delete_old_aoms(aom_to_add, aoms)

          # we load the join on cities
          import_insee_aom()
          enable_trigger()
        end,
        timeout: 1_000_000
      )

    # we can then compute the aom geometries (the union of each cities geometries)
    compute_geom()

    :ok
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
    # credo:disable-for-next-line
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
    aom_to_add |> Enum.each(fn {_id, aom} -> Repo.insert_or_update!(aom) end)
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

    aom_ids = AOM |> select([a], {a.siren, a.composition_res_id}) |> Repo.all() |> Enum.into(%{})

    stream
    |> IO.binstream(:line)
    |> CSV.decode(separator: ?,, headers: true)
    |> Enum.map(fn {:ok, line} -> {line["siren_aom"], line["insee"]} end)
    |> Enum.reject(fn {aom_siren, insee} -> aom_siren == "" || insee == "" || aom_siren not in Map.keys(aom_ids) end)
    |> Enum.map(fn {aom_siren, insee} -> {aom_ids[aom_siren], insee} end)
    |> Enum.flat_map(fn {aom, insee} ->
      # To reduce the number of UPDATE in the DB, we first check which city needs to be updated
      Commune
      |> where([c], c.insee == ^insee and (c.aom_res_id != ^aom or is_nil(c.aom_res_id)))
      |> select([c], c.id)
      |> Repo.all()
      |> Enum.map(fn c -> {aom, c} end)
    end)
    |> Enum.reduce(%{}, fn {aom, commune}, commune_by_aom ->
      # Then we group those city by AO, to only do one UPDATE query for several cities
      commune_by_aom
      |> Map.update(aom, [commune], fn list_communes -> [commune | list_communes] end)
    end)
    |> Enum.map(fn {aom, list_communes} ->
      Commune
      |> where([c], c.id in ^list_communes)
      |> Repo.update_all(set: [aom_res_id: aom])
    end)
  end

  defp compute_geom do
    Logger.info("computing AOM geometries")

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
      [],
      timeout: 1_000_000
    )
  end

  defp disable_trigger do
    Repo.query!("ALTER TABLE aom DISABLE TRIGGER refresh_places_aom_trigger;")
    Repo.query!("ALTER TABLE commune DISABLE TRIGGER refresh_places_commune_trigger;")
  end

  defp enable_trigger do
    Repo.query!("ALTER TABLE aom ENABLE TRIGGER refresh_places_aom_trigger;")
    Repo.query!("ALTER TABLE commune ENABLE TRIGGER refresh_places_commune_trigger;")
    Repo.query!("REFRESH MATERIALIZED VIEW places;")
  end

  defp migrate_aoms do
    queries = """
    -- Sainte-Menehould to CC de l'Argonne Champenoise
    update dataset set aom_id = (select id from aom where composition_res_id = 1163) where aom_id = 121;
    -- Vierzon to région CVL
    update dataset set aom_id = null, region_id = (select id from region where nom = 'Centre-Val de Loire') where aom_id = 126;
    -- Sablé-sur-Sarthe to Communauté de communes du Pays Sabolien
    update dataset set aom_id = (select id from aom where composition_res_id = 1290) where aom_id = 137;
    -- Langres to PETR du Pays de Langres
    update dataset set aom_id = (select id from aom where composition_res_id = 1172) where aom_id = 149;
    -- Mayenne to CC Mayenne Communauté
    update dataset set aom_id = (select id from aom where composition_res_id = 1277) where aom_id = 173;
    -- Douarnenez to CC Douarnenez Communauté
    update dataset set aom_id = (select id from aom where composition_res_id = 1375) where aom_id = 175;
    -- Obernai to CC du Pays de Sainte-Odile
    update dataset set aom_id = (select id from aom where composition_res_id = 1235) where aom_id = 210;
    -- Nogent-le-Rotrou to CVL region
    update dataset set aom_id = null, region_id = (select id from region where nom = 'Centre-Val de Loire') where aom_id = 215;
    -- Mende, Figeac to Occitanie region
    update dataset set aom_id = null, region_id = (select id from region where nom = 'Occitanie') where aom_id in (222, 223);
    -- Tignes to Auvergne-Rhône-Alpes region
    update dataset set aom_id = null, region_id = (select id from region where nom = 'Auvergne-Rhône-Alpes') where aom_id = 242;
    -- Bernay to CC Intercom Bernay Terres de Normandie
    update dataset set aom_id = (select id from aom where composition_res_id = 1108) where aom_id = 245;
    -- Sud Estuaire to CC du Sud Estuaire
    update dataset set aom_id = (select id from aom where composition_res_id = 1268) where aom_id = 246;
    -- Oloron Sainte-Marie to CC du Haut Béarn
    update dataset set aom_id = (select id from aom where composition_res_id = 1434) where aom_id = 248;
    -- Granville to CC de Granville, Terre et Mer
    update dataset set aom_id = (select id from aom where composition_res_id = 1114) where aom_id = 305;
    -- Neufchâteau to CC de l'Ouest Vosgien
    update dataset set aom_id = (select id from aom where composition_res_id = 1254) where aom_id = 304;
    """

    queries |> String.split(";") |> Enum.each(&Repo.query!/1)
  end
end
