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

  The import can be launched from the site backoffice, or through Transport.ImportAOMs.run()
  """

  import Ecto.{Query}
  alias DB.{AOM, Commune, Region, Repo}
  require Logger

  # The 2 community resources stable urls
  # To create the following file: just rename columns and export as CSV, no content modification needed
  @aom_file "https://gist.githubusercontent.com/vdegove/42d134c59b286525ff412876be3b6547/raw/d631b46c9096c148d854fbd5e9710987efb22999/base-rt-2023-diffusion-v2-aoms.csv"
  # To create the following file: just delete useless columns and export as CSV, no content modification needed
  @aom_insee_file "https://gist.githubusercontent.com/vdegove/42d134c59b286525ff412876be3b6547/raw/d631b46c9096c148d854fbd5e9710987efb22999/base-rt-2023-diffusion-v2-communes.csv"

  @ignored_aom_ids ["312"] # We don’t add collectivité d’outremer de Saint-Martin

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
    nom = String.trim(line["Nom"])
    new_region = Repo.get_by(Region, nom: normalize_region(line["Région"]))

    if !is_nil(aom.region) and !is_nil(new_region) and aom.region != new_region do
      Logger.info("aom #{nom} || previous region #{aom.region.nom} --- #{new_region.nom}")
    end

    external_id = to_int(line["Id réseau"])

    {external_id,
     Ecto.Changeset.change(aom, %{
       composition_res_id: external_id,
       departement: extract_departement_insee(line["Département"]),
       siren: line["N° SIREN"] |> String.trim(),
       nom: nom,
       forme_juridique: normalize_forme(line["Forme juridique"]),
       nombre_communes: to_int(line["Nombre de communes"]), # This is inconsistent with the real number of communes…
       population: to_int(line["Population"]),
       surface: line["Surface (km²)"] |> String.trim(),
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

  defp extract_departement_insee("977 - Collectivité d’outre-mer de Nouvelle Calédonie"), do: "988" # Oups
  defp extract_departement_insee(insee_and_name), do: insee_and_name |> String.split(" - ") |> hd() |> String.trim

  def run do
    old_aoms =
      AOM
      |> Repo.all()
      |> Map.new(fn aom -> {aom.composition_res_id, aom} end)

    # get all the aom to import, outside of the transaction to reduce the time in the transaction
    # this already builds the changeset
    aoms_to_add = get_aom_changeset_to_import() # Mapset of {composition_res_id, changeset}

    mapset_first_elem_diff = fn (a, b) -> a |> MapSet.new(&elem(&1, 0)) |> MapSet.difference(b |> MapSet.new(&elem(&1, 0))) end
    new_aoms = mapset_first_elem_diff.(aoms_to_add, old_aoms)
    removed_aoms = mapset_first_elem_diff.(old_aoms, aoms_to_add)
    Logger.info("#{new_aoms |> Enum.count} new AOMs. reseau_id codes: #{Enum.join(new_aoms, ", ")}")
    Logger.info("#{removed_aoms |> Enum.count} removed AOMs. reseau_id codes: #{Enum.join(removed_aoms, ", ")}")

    # Some Ecto fun: two ways of joining through assoc, see https://hexdocs.pm/ecto/associations.html
    deleted_aom_datasets = DB.Dataset
    |> join(:left, [d], aom in assoc(d, :aom))
    |> where([d, aom], aom.composition_res_id in ^(removed_aoms |> MapSet.to_list()))
    |> select([d, aom], [aom.id, aom.composition_res_id, d.id])
    |> DB.Repo.all()
    |> Enum.group_by(&hd(&1))
    Logger.info("Datasets still associated with deleted AOM as territory : #{inspect(deleted_aom_datasets)}")

    deleted_legal_owners = (
      from d in DB.Dataset,
      join: aom in assoc(d, :legal_owners_aom), # This magically works with the many_to_many
      where: aom.composition_res_id in  ^(removed_aoms |> MapSet.to_list()),
      select: [aom.id, aom.composition_res_id, d.id]
      ) |> DB.Repo.all() |> Enum.group_by(&hd(&1))
    Logger.info("Datasets still associated with deleted AOM as legal owner: #{inspect(deleted_legal_owners)}")



    {:ok, _} =
      Repo.transaction(
        fn ->
          disable_trigger()
          # we load all aoms
          import_aoms(aoms_to_add)
          # Some datasets should change AOM
          migrate_datasets_to_new_aoms()
          delete_old_aoms(aoms_to_add, old_aoms)

          # TODO: add commune_principale to AOM

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

  defp get_aom_changeset_to_import do
    Logger.info("importing aoms")

    {:ok, %HTTPoison.Response{status_code: 200, body: body}} =
      HTTPoison.get(@aom_file, [], hackney: [follow_redirect: true])

    {:ok, stream} = StringIO.open(body)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(separator: ?,, headers: true, validate_row_length: true)
    |> Enum.reject(fn {:ok, line} -> line["Id réseau"] in (["", nil] ++ @ignored_aom_ids) end)
    |> Enum.map(fn {:ok, line} ->
      existing_or_new_aom(line) |> Repo.preload(:region) |> changeset(line)
    end)
    |> MapSet.new()
  end

  defp existing_or_new_aom(line) do
    AOM
      |> Repo.get_by(composition_res_id: to_int(line["Id réseau"]))
      |> case do
        nil ->
          %AOM{}

        aom ->
          aom
      end
  end

  defp import_aoms(aoms_to_add) do
    aoms_to_add |> Enum.each(fn {_id, aom} -> Repo.insert_or_update!(aom) end)
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
    |> CSV.decode(separator: ?,, headers: true, validate_row_length: true)
    |> Enum.map(fn {:ok, line} -> {line["N° INSEE"], line["Id réseau"]} end)
    |> Enum.reject(fn {_insee, id_reseau} -> id_reseau == "" || id_reseau == "-" end)
    |> Enum.flat_map(fn {insee, id_reseau} ->
      # To reduce the number of UPDATE in the DB, we first check which city needs to be updated
      Commune
      |> where([c], c.insee == ^insee and (c.aom_res_id != ^id_reseau or is_nil(c.aom_res_id)))
      |> select([c], c.id)
      |> Repo.all()
      |> Enum.map(fn c -> {c, id_reseau} end)
    end)
    |> Enum.reduce(%{}, fn {commune, aom}, commune_by_aom ->
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


  defp migrate_datasets_to_new_aoms do
    queries = """
    -- This could be mostly automatized, you just have to look for a commune of the old AOM and see where it was migrated.
    -- 2022
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
    --
    -- 2023
    -- [info] Datasets still associated with deleted AOM as territory :
    -- %{230 => [[230, 275, 401]], 449 => [[449, 1509, 653]]}
    -- [info] Datasets still associated with deleted AOM as legal owner:
    -- %{230 => [[230, 275, 401], [230, 275, 338]],
    -- 440 => [[440, 1475, 732]],
    -- 449 => [[449, 1509, 653], [449, 1509, 787]],
    -- 558 => [[558, 1469, 732]],
    -- 677 => [[677, 1478, 732]]}
    -- CC du Pays d'Issoudun (id : 230, res_id: 275) to Région Centre-Val de Loire (CC du Pays d'Issoudun) (res_id: 13608)
    -- Migrates this dataset as both territory and legal owner https://transport.data.gouv.fr/datasets/issoudun-offre-theorique-mobilite-reseau-urbain
    -- This one as legal owner https://transport.data.gouv.fr/datasets/arrets-itineraires-et-horaires-theoriques-des-reseaux-de-transport-des-membres-de-jvmalin
    update dataset set aom_id = (select id from aom where composition_res_id = 13608) where aom_id = 230;
    update dataset_aom_legal_owner set aom_id = (select id from aom where composition_res_id = 13608) where aom_id = 230;
    -- CC Arve et Salève (id : 440, res_id: 1475) to SM4CC (res_id: 417)
    -- CC Faucigny-Glières (id: 558, res_id :1509 to SM4CC (res_id: 417)
    -- CC du Pays Rochois (id: 677, res_id: 1478 to SM4CC (res_id: 417)
    -- There is a fourth CC in SM4CC, CC des Quatre Rivières (haute savoie)
    -- Removes aggregate legal owner here https://transport.data.gouv.fr/datasets/agregat-oura but keeps SM4CC
    delete from dataset_aom_legal_owner where aom_id in (440, 558, 677);
    -- L'Île-d'Yeu (id: 449, res_id: 1509) to ILE D'YEU (res_id: 310);
    -- Strange that res_id changes…
    update dataset set aom_id = (select id from aom where composition_res_id = 310) where aom_id = 449;
    update dataset_aom_legal_owner set aom_id = (select id from aom where composition_res_id = 310) where aom_id = 449;
    """

    queries |> String.split(";") |> Enum.each(&Repo.query!/1)
  end
end
