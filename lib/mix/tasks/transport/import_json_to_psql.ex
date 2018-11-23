defmodule Mix.Tasks.Transport.ImportJson do
  @moduledoc """
  Import bson files to psql
  """

  use Mix.Task
  alias Transport.{AOM, Dataset, Region, Repo}

  @shortdoc "Import mongouri to psql"
  def run([mongo_uri]) do
    System.cmd("mongoexport", ["--uri", mongo_uri, "-o", "/tmp/regions.json", "-c", "regions"])
    System.cmd("mongoexport", ["--uri", mongo_uri, "-o", "/tmp/aoms.json", "-c", "aoms"])
    System.cmd("mongoexport", ["--uri", mongo_uri, "-o", "/tmp/datasets.json", "-c", "datasets"])
    Mix.Task.run "app.start"

    read_and_insert("/tmp/regions.json", &new_region/1)
    read_and_insert("/tmp/aoms.json", &new_aom/1)
    read_and_insert("/tmp/datasets.json", &new_dataset/1)
  end

  def new_region(%{"geometry" => geometry,
                   "properties" => %{"NOM_REG" => nom, "INSEE_REG" => insee,
                    "completed" => is_completed}}) do
    %Region{
      nom: normalize_region(nom),
      insee: insee,
      geometry: geometry,
      is_completed: is_completed
    }
  end
  def new_region(%{"geometry" => geom, "properties" => props}) do
    new_region(%{"geometry" => geom, "properties" => Map.put(props, "completed", nil)})
  end

  def new_aom(%{"geometry" => geometry, "properties" => props}) do
    %AOM{
      composition_res_id: props["compositions_res_id"],
      insee_commune_principale: props["liste_aom_Code INSEE Commune Principale"],
      region: Repo.get_by!(Region, nom: normalize_region(props["liste_aom_Nouvelles régions"])),
      departement: props["liste_aom_dep"],
      siren: props["liste_aom_N° SIREN"],
      nom: props["liste_aom_Nom de l’AOM"],
      forme_juridique: props["liste_aom_Forme juridique 2017"],
      nombre_communes:
        props["liste_aom_Nombre de communes du RT"]
        |> String.replace(",", "")
        |> String.to_integer,
      population_muni_2014: props["liste_aom_Population Municipale 2014"] |> parse_population,
      population_totale_2014: props["liste_aom_Population Totale 2014"] |> parse_population,
      surface: props["liste_aom_Surface (km²)"],
      commentaire: props["liste_aom_Commentaire"],
      geometry: geometry
    }
  end

  def new_dataset(%{"slug" => _slug} = props) do
    %Dataset{
      coordinates: props["coordinates"],
      datagouv_id: props["datagouv_id"],
      spatial: props["spatial"],
      created_at: props["created_at"],
      description: props["description"],
      download_url: props["download_url"],
      format: props["format"],
      frequency: props["frequency"],
      last_update: props["last_update"],
      last_import: props["last_import"],
      licence: props["licence"],
      logo: props["logo"],
      full_logo: props["full_logo"],
      slug: props["slug"],
      tags: props["tags"],
      task_id: props["task_id"],
      title: props["title"],
      metadata: props["metadata"],
      validations: %{
        "CloseStops" => props["CloseStops"],
        "NullDuration" => props["NullDuration"],
        "UnsedStop" => props["UnusedStops"],
      },
      validation_date: props["validation_date"],
      aom: Repo.get_by(AOM, insee_commune_principale: props["commune_principale"]),
      region: get_region_name(props)
    }
  end
  def new_dataset(_), do: nil

  def read_and_insert(filename, func) do
    filename
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.map(&Poison.decode!/1)
    |> Stream.map(func)
    |> Stream.reject(&is_nil/1)
    |> Stream.map(&Repo.insert/1)
    |> Stream.run()
  end

  def parse_population(population), do: population |> String.replace(",", "") |> String.to_integer()

  defp get_region_name(%{"region" => "National"}), do: nil
  defp get_region_name(%{"region" => region}), do: Repo.get_by!(Region, nom: normalize_region(region))

  defp normalize_region("Grand-Est"), do: "Grand Est"
  defp normalize_region("Provence-Alpes-Côte-d'Azur"), do: "Région Sud — Provence-Alpes-Côte d’Azur"
  defp normalize_region("Nouvelle Aquitaine"), do: "Nouvelle-Aquitaine"
  defp normalize_region("Auvergne-Rhône Alpes"), do: "Auvergne-Rhône-Alpes"
  defp normalize_region(region), do: region
end
