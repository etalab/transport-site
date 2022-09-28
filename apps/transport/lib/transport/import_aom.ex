defmodule Transport.ImportAOMs do
  @moduledoc """
  Import the AOM files and updates the database

  The aom files are custom made from an excel file from the Cerema
  https://www.data.gouv.fr/fr/datasets/liste-et-composition-des-autorites-organisatrices-de-la-mobilite-aom/

  and pushed as community ressource on data.gouv.
  There are 2 files:
  - one with the description of each aom
  - one with the list of cities that are part of each aom

  This is a one shot import task, run when the aom have changed.

  The import can be launched from the site backoffice
  """

  import Ecto.{Query}
  alias DB.{AOM, Commune, Region, Repo}
  require Logger

  # The 2 community resources stable urls
  @aom_file "https://gist.github.com/AntoineAugusti/cc20763ee572508c6785666908c2a8de/raw/1dca321bcf08fcbece4db5a8a303ff98de84ea6f/aoms_2022.csv"
  @aom_insee_file "https://gist.github.com/AntoineAugusti/cc20763ee572508c6785666908c2a8de/raw/1dca321bcf08fcbece4db5a8a303ff98de84ea6f/aom_insee_fix.csv"

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
    # some names have been manually set, we want to keep them
    IO.inspect(line)
    insee = (Repo.get_by(Commune, siren: line["Code INSEE Commune principale"]) || Repo.get_by(Commune, insee: line["Code INSEE Commune principale"])).insee

    nom = line["Nom de l’AOM"]

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

          delete_old_aoms(aom_to_add, aoms)

          # we load the join on cities
          import_insee_aom()
          enable_trigger()
        end,
        timeout: 400_000
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
    |> Enum.reject(fn {:ok, line} -> line["Id réseau"] in ["", "312"] end)
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

    aom_ids = AOM |> select([a], a.composition_res_id) |> Repo.all()

    stream
    |> IO.binstream(:line)
    |> CSV.decode(separator: ?,, headers: true)
    |> Enum.map(fn {:ok, line} -> {String.to_integer(line["Id réseau"]), line["N° INSEE"]} end)
    |> Enum.reject(fn {aom, insee} -> aom == "" || insee == "" || aom not in aom_ids end)
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
      [],
      timeout: 240_000
    )
  end

  defp disable_trigger, do: Repo.query!("ALTER TABLE aom DISABLE TRIGGER refresh_places_aom_trigger;")

  defp enable_trigger do
    Repo.query!("ALTER TABLE aom DISABLE TRIGGER refresh_places_aom_trigger;")
    Repo.query!("REFRESH MATERIALIZED VIEW places;")
  end
end
# [info] trying to delete old aom: 121 - Sainte-Menehould
# [info] trying to delete old aom: 126 - Vierzon
# [info] trying to delete old aom: 130 - Honfleur
# [info] trying to delete old aom: 137 - Sablé-sur-Sarthe
# [info] trying to delete old aom: 144 - Sainte-Marie-aux-Mines
# [info] trying to delete old aom: 149 - Langres
# [info] trying to delete old aom: 157 - Saint-Claude
# [info] trying to delete old aom: 170 - Pontarlier
# [info] trying to delete old aom: 172 - Fontenay-le-Comte
# [info] trying to delete old aom: 173 - Mayenne
# [info] trying to delete old aom: 174 - Sarlat-la-Caneda
# [info] trying to delete old aom: 175 - Douarnenez
# [info] trying to delete old aom: 176 - Châteaudun
# [info] trying to delete old aom: 179 - Argentan
# [info] trying to delete old aom: 180 - Bellegarde-sur-Valserine
# [info] trying to delete old aom: 182 - Orange
# [info] trying to delete old aom: 193 - Bollène
# [info] trying to delete old aom: 195 - Bouzonville
# [info] trying to delete old aom: 198 - Crépy-en-Valois
# [info] trying to delete old aom: 203 - L’Île d’Yeu
# [info] trying to delete old aom: 206 - Vire Normandie
# [info] trying to delete old aom: 209 - Senlis
# [info] trying to delete old aom: 210 - Obernai
# [info] trying to delete old aom: 212 - Remiremont
# [info] trying to delete old aom: 215 - Nogent-le-Rotrou
# [info] trying to delete old aom: 218 - Landernau
# [info] trying to delete old aom: 222 - Mende
# [info] trying to delete old aom: 223 - Figeac
# [info] trying to delete old aom: 234 - Saint Amand Montrond
# [info] trying to delete old aom: 237 - Péronne
# [info] trying to delete old aom: 240 - CC Cœur de Maurienne Arvan
# [info] trying to delete old aom: 242 - Tignes
# [info] trying to delete old aom: 243 - Pont-Audemer
# [info] trying to delete old aom: 245 - Bernay
# [info] trying to delete old aom: 246 - Sud Estuaire
# [info] trying to delete old aom: 247 - Sorgues
# [info] trying to delete old aom: 248 - Oloron Sainte-Marie
# [info] trying to delete old aom: 249 - Ambérieu-en-Bugey
# [info] trying to delete old aom: 253 - Val d’Isère
# [info] trying to delete old aom: 254 - Bourg-saint-Maurice
# [info] trying to delete old aom: 255 - Aime-la-plagne
# [info] trying to delete old aom: 256 - La Plagne – Tarentaise
# [info] trying to delete old aom: 257 - Montmélian
# [info] trying to delete old aom: 259 - CC de Cœur de Tarentaise
# [info] trying to delete old aom: 260 - Noyon
# [info] trying to delete old aom: 261 - Luxeuil les Bains
# [info] trying to delete old aom: 262 - Yvetot
# [info] trying to delete old aom: 264 - La Tour du Pin
# [info] trying to delete old aom: 268 - Les Avanchers–Valmorel
# [info] trying to delete old aom: 276 - Saint-Hilaire-de-Riez
# [info] trying to delete old aom: 277 - Sorède
# [info] trying to delete old aom: 282 - Saint-Gilles-Croix-de-Vie
# [info] trying to delete old aom: 285 - Challans
# [info] trying to delete old aom: 293 - Luçon
# [info] trying to delete old aom: 296 - Les Deux Alpes
# [info] trying to delete old aom: 298 - Argelès-sur-Mer
# [info] trying to delete old aom: 299 - Bagnoles de l’Orne
# [info] trying to delete old aom: 3 - CC de Belle-Île-en-Mer
# [info] trying to delete old aom: 304 - Neufchâteau
# [info] trying to delete old aom: 305 - Granville
# [info] trying to delete old aom: 306 - Nyons
# [info] trying to delete old aom: 307 - Liancourt
# [info] trying to delete old aom: 308 - Paray-le-Monial
# [info] trying to delete old aom: 327 - Collectivité de Saint-Martin Antilles Françaises
# [info] trying to delete old aom: 400 - Porto Vecchio
# [info] trying to delete old aom: 86 - Briançon
