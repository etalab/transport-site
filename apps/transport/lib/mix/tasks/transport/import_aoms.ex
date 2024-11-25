defmodule Mix.Tasks.Transport.ImportAOMs do
  @moduledoc """
  Import the AOM files and updates the database.

  The AOM files come from the Cerema dataset:
  https://www.data.gouv.fr/fr/datasets/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/
  https://www.cerema.fr/fr/actualites/liste-composition-autorites-organisatrices-mobilite-au-1er-4

  and pushed as community resources on data.gouv.fr.
  There are 2 files:
  - one with the description of each AOM
  - one with the list of cities that are part of each AOM

  This is a one shot import task, run when the AOM have changed, at least every year.

  The import can be launched through mix Transport.ImportAOMs
  """

  @shortdoc "Refreshes the database table `aom` with the latest data"
  use Mix.Task
  import Ecto.{Query}
  alias DB.{AOM, Commune, Region, Repo}
  require Logger

  # The resources urls
  # To create the following file:
  # download the Cerema file (.ods)
  # rename columns that are on two lines
  # export as CSV and publish as community resource
  @aom_file "https://static.data.gouv.fr/resources/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/20241108-105224/liste-aoms-2024.csv"
  # Same for composition of each AOM, but no need even to rename columns
  @aom_insee_file "https://static.data.gouv.fr/resources/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/20241122-154942/composition-communale-aom-2024.csv"

  # We don’t add collectivité d’outremer de Saint-Martin
  @ignored_aom_ids ["312"]

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

  @spec changeset(map()) :: {integer(), Ecto.Changeset.t()}
  def changeset(line) do
    aom = line |> existing_or_new_aom() |> Repo.preload(:region)

    nom = normalize_nom(String.trim(line["Nom"]))
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
       # This is inconsistent with the real number of communes for some lines
       nombre_communes: to_int(line["Nombre de communes"]),
       population: to_int(line["Population"]),
       # Database stores a string, we could use a float
       surface: line["Surface (km²)"] |> String.trim() |> String.replace(",", "."),
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
  defp normalize_forme("METRO"), do: "Métropole"
  defp normalize_forme("PETR"), do: "Pôle d'équilibre territorial et rural"
  defp normalize_forme(f), do: f

  @spec normalize_nom(binary()) :: binary()
  defp normalize_nom("SIVOTU (nouvelle dénomination le 24/02/2010:AGGLOBUS)"), do: "Agglobus"
  defp normalize_nom("ILE D'YEU"), do: "L'Île-d'Yeu"
  defp normalize_nom(n), do: n

  # Oups
  defp extract_departement_insee("977 - Collectivité d’outre-mer de Nouvelle Calédonie"), do: "988"
  defp extract_departement_insee(insee_and_name), do: insee_and_name |> String.split(" - ") |> hd() |> String.trim()

  def run(_params) do
    Logger.info("Starting AOM import")
    Mix.Task.run("app.start")

    old_aoms =
      AOM
      |> Repo.all()
      |> Map.new(fn aom -> {aom.composition_res_id, aom} end)

    # get all the aom to import, outside of the transaction to reduce the time in the transaction
    # this already builds the changeset
    # Mapset of {composition_res_id, changeset}
    aoms_to_add = get_aom_to_import() |> Enum.map(&changeset/1) |> MapSet.new()

    display_changes(old_aoms, aoms_to_add)

    {:ok, _} =
      Repo.transaction(
        fn ->
          disable_trigger()
          # we load all aoms
          import_aoms(aoms_to_add)
          # Some datasets should change AOM
          migrate_datasets_to_new_aoms(2024)
          delete_old_aoms(aoms_to_add, old_aoms)
          # we load the join on cities
          import_insee_aom()
          enable_trigger()
        end,
        timeout: 1_000_000
      )

    # we can then compute the aom geometries (the union of each cities geometries)
    compute_geom()
    set_main_commune()

    :ok
  end

  defp get_aom_to_import do
    Logger.info("Importing Cerema file…")

    {:ok, %HTTPoison.Response{status_code: 200, body: body}} =
      HTTPoison.get(@aom_file, [], hackney: [follow_redirect: true])

    {:ok, stream} = StringIO.open(body)

    stream
    |> IO.binstream(:line)
    |> CSV.decode(separator: ?,, headers: true, validate_row_length: true)
    |> Enum.map(fn {:ok, line} -> line end)
    |> Enum.reject(fn line -> line["Id réseau"] in (["", nil] ++ @ignored_aom_ids) end)
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
    Logger.info("importing AOMs…")
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

  def set_main_commune do
    Logger.info("set main commune")

    max_for_each_aom =
      from(c in DB.Commune,
        where: not is_nil(c.aom_res_id),
        group_by: c.aom_res_id,
        select: %{aom_res_id: c.aom_res_id, max_population: max(c.population)}
      )

    main_communes =
      from(c in DB.Commune,
        where: not is_nil(c.aom_res_id),
        join: max_for_each_aom in subquery(max_for_each_aom),
        on: c.aom_res_id == max_for_each_aom.aom_res_id and c.population == max_for_each_aom.max_population,
        select: [c.aom_res_id, c.insee]
      )

    main_communes =
      main_communes
      |> DB.Repo.all()
      |> MapSet.new(fn [aom_res_id, insee] -> {aom_res_id, insee} end)

    {:ok, _} =
      Repo.transaction(
        fn ->
          disable_trigger()

          main_communes
          |> Enum.each(fn {aom_res_id, insee} ->
            AOM
            |> Repo.get_by!(composition_res_id: aom_res_id)
            |> Ecto.Changeset.change(%{insee_commune_principale: insee})
            |> Repo.update()
          end)

          enable_trigger()
        end,
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

  # This could be mostly automatized, you just have to look for a commune of the old AOM and see where it was migrated.
  defp migrate_datasets_to_new_aoms(2023) do
    queries = """
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
    -- L'Île-d'Yeu (id: 449, res_id: 1509) to L’Île-d’Yeu (res_id: 310);
    update dataset set aom_id = (select id from aom where composition_res_id = 310) where aom_id = 449;
    update dataset_aom_legal_owner set aom_id = (select id from aom where composition_res_id = 310) where aom_id = 449;
    --
    -- 2024
    -- Migrates a dataset to Pôle Métropolitain Mobilités Le Mans – Sarthe
    update dataset_aom_legal_owner set aom_id = (select id from aom where composition_res_id = 1293) where aom_id IN (1283, 1285, 1288, 1292, 1294);
    """

    queries |> String.split(";") |> Enum.each(&Repo.query!/1)
  end

  defp migrate_datasets_to_new_aoms(2024) do
    queries = """
    -- Migrates a dataset to Pôle Métropolitain Mobilités Le Mans – Sarthe
    update dataset_aom_legal_owner set aom_id = (select id from aom where composition_res_id = 1293) where aom_id IN (1283, 1285, 1288, 1292, 1294);
    """

    queries |> String.split(";") |> Enum.each(&Repo.query!/1)
  end

  defp display_changes(old_aoms, aoms_to_add) do
    mapset_first_elem_diff = fn a, b ->
      a |> MapSet.new(&elem(&1, 0)) |> MapSet.difference(b |> MapSet.new(&elem(&1, 0)))
    end

    new_aoms = mapset_first_elem_diff.(aoms_to_add, old_aoms)
    removed_aoms = mapset_first_elem_diff.(old_aoms, aoms_to_add)
    Logger.info("#{new_aoms |> Enum.count()} new AOMs. reseau_id codes: #{Enum.join(new_aoms, ", ")}")
    Logger.info("#{removed_aoms |> Enum.count()} removed AOMs. reseau_id codes: #{Enum.join(removed_aoms, ", ")}")

    # Some Ecto fun: two ways of joining through assoc, see https://hexdocs.pm/ecto/associations.html
    deleted_aom_datasets =
      DB.Dataset
      |> join(:left, [d], aom in assoc(d, :aom))
      |> where([d, aom], aom.composition_res_id in ^(removed_aoms |> MapSet.to_list()))
      |> select([d, aom], [aom.id, aom.composition_res_id, d.id])
      |> DB.Repo.all()
      |> Enum.group_by(&hd(&1))

    Logger.info(
      "Datasets still associated with deleted AOM as territory (aom.id => [aom.id, aom.composition_res_id, dataset.id]) : #{inspect(deleted_aom_datasets)}"
    )

    deleted_legal_owners_query =
      from(d in DB.Dataset,
        # This magically works with the many_to_many
        join: aom in assoc(d, :legal_owners_aom),
        where: aom.composition_res_id in ^(removed_aoms |> MapSet.to_list()),
        select: [aom.id, aom.composition_res_id, d.id]
      )

    deleted_legal_owners = deleted_legal_owners_query |> DB.Repo.all() |> Enum.group_by(&hd(&1))

    Logger.info(
      "Datasets still associated with deleted AOM as legal owner (aom.id => [aom.id, aom.composition_res_id, dataset.id]): #{inspect(deleted_legal_owners)}"
    )
  end
end
