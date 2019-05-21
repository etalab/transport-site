defmodule Mix.Tasks.Transport.ImportAom do
  @moduledoc """
  Import the AOM files and updates the database
  """

  use Mix.Task
  alias Ecto.Changeset
  alias Transport.{AOM, Region, Repo}

  def to_int(str) do
    str
    |> String.replace(",", "")
    |> String.replace(".", "")
    |> String.replace(" ", "")
    |> String.to_integer
  end

  def changeset(aom, line) do
    Changeset.change(aom, %{
      composition_res_id: to_int(line["Id réseau"]),
      insee_commune_principale: line["Code INSEE Commune Principale"],
      departement: line["dep"],
      siren: to_int(line["N° SIREN"]),
      nom: line["Nom de l’AOM"],
      forme_juridique: line["Forme juridique 2017"],
      nombre_communes: to_int(line["Nombre de communes du RT"]),
      population_muni_2014: to_int(line["Population Municipale 2014"]),
      population_totale_2014: to_int(line["Population Totale 2014"]),
      surface: line["Surface (km²)"],
      commentaire: line["Commentaire"],
      region: Repo.get_by(Region, nom: normalize_region(line["Nouvelles régions"]))
    })
  end

  defp normalize_region("Grand-Est"), do: "Grand Est"
  defp normalize_region("Provence-Alpes-Côte-d'Azur"), do: "Région Sud — Provence-Alpes-Côte d’Azur"
  defp normalize_region("Nouvelle Aquitaine"), do: "Nouvelle-Aquitaine"
  defp normalize_region("Auvergne-Rhône Alpes"), do: "Auvergne-Rhône-Alpes"
  defp normalize_region(region), do: region

  def run(params) do
    if params[:no_start] do
      HTTPoison.start
    else
      Mix.Task.run("app.start", [])
    end
    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- HTTPoison.get("https://www.data.gouv.fr/fr/datasets/r/42625320-bc2d-4368-8c00-3e28dbf7f51a", [], hackney: [follow_redirect: true]),
         {:ok, stream} <- StringIO.open(body) do
      stream
      |> IO.binstream(:line)
      |> CSV.decode(separator: ?\t, headers: true)
      |> Enum.filter(fn {:ok, line} -> line["Id réseau"] != "" end)
      |> Enum.each(fn {:ok, line} ->
        AOM
        |> Repo.get_by(composition_res_id: to_int(line["Id réseau"]))
        |> case do
          nil -> %AOM{}
          aom -> aom
          |> Repo.preload(:region)
        end
        |> changeset(line)
        |> Repo.insert_or_update
      end)
    end
  end
end
