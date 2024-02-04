#! /usr/bin/env mix run

# the basis of a mass-analysis script for IRVE files,
# inspired by https://github.com/etalab/notebooks/blob/master/irve-v2/consolidation-irve-v2.ipynb

require Logger

Logger.info("Retrieving each relevant datagouv page & listing resources")

resources = Transport.IRVE.Main.resources()

Logger.info("Sharing a few stats...")

if System.get_env("SHOW_STATS") == "1" do
  IO.puts("=== Sample ===")
  resources |> Enum.take(2) |> IO.inspect(IEx.inspect_opts())

  IO.puts("=== Stats ===")
  IO.inspect(%{count: resources |> length}, IEx.inspect_opts() |> Keyword.put(:label, "total_count"))

  # M'a aidé à me rendre compte que.. un gros paquet est invalide!
  resources
  |> Enum.frequencies_by(fn x -> x[:valid] end)
  |> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:valid)"))

  resources
  |> Enum.frequencies_by(fn x -> x[:valid] end)
  |> Enum.map(fn {_, v} -> ((100 * v / (resources |> length)) |> trunc() |> to_string) <> "%" end)
  |> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:valid) as %"))

  # M'a aidé à me rendre compte que... il y avait plusieurs schémas, car on recherche par "dataset",
  # mais après on travaille au niveau ressources, et donc on cherche par le "schéma de chaque ressource du dataset",
  # ce qui fait qu'il y a des choses en trop.
  resources
  |> Enum.frequencies_by(fn x -> x[:schema_name] end)
  |> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:schema_name)"))

  resources
  |> Enum.frequencies_by(fn x -> x[:schema_version] end)
  |> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:schema_version)"))

  resources
  |> Enum.frequencies_by(fn x -> x[:filetype] end)
  |> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:filetype)"))
end

Logger.info("Fetching each IRVE resource so that we can retrieve PDC count... (must be parallelized, otherwise awful)")

resources =
  resources
  |> Enum.with_index()
  |> Enum.map(fn {x, index} ->
    IO.puts("Processing #{index}...")

    # TODO: parallelize this part (for production, uncached)
    %{status: status, body: body} =
      Transport.IRVE.Streamer.get!(x[:url], compressed: false, decode_body: false)

    x = x |> Map.put(:status, status)

    if status == 200 do
      body = body |> String.split("\n")

      first_line =
        body
        |> hd()

      line_count = (body |> length) - 1

      id_detected = first_line |> String.contains?("id_pdc_itinerance")
      # a field from v1, which does not end like a field in v2
      old_schema = first_line |> String.contains?("ad_station")

      x
      |> Map.put(:id_pdc_itinerance_detected, id_detected)
      |> Map.put(:old_schema, old_schema)
      |> Map.put(:first_line, first_line)
      |> Map.put(:line_count, line_count)
    else
      x
    end
  end)
  |> Enum.reject(fn x -> is_nil(x) end)
  |> Enum.map(fn x ->
    Map.take(x, [:dataset_id, :valid, :line_count])
  end)

Logger.info("Doing more stats...")

resources
# |> Enum.filter(fn x -> x[:id_pdc_itinerance_detected] == true && x[:old_schema] == true end)
|> Enum.frequencies_by(fn x -> Map.take(x, [:id_pdc_itinerance_detected, :old_schema]) end)
|> IO.inspect()

# Format pourris ?
# Ancien schéma ? (en étant sûr)
# => Les invalides avec le bon format ?
# Tableau de pilotage
# invalides 2.2.0 ->

recent_stuff =
  resources
  |> Enum.filter(fn x -> x[:id_pdc_itinerance_detected] end)

recent_stuff
|> Enum.frequencies_by(fn x -> x[:valid] end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:valid)"))

# TODO: voir ce qui se passe avec un valide à l'écran dans data gouv

recent_stuff
|> Enum.filter(fn x -> x[:valid] == false end)
|> Enum.sort_by(fn x -> -x[:line_count] end)
|> Enum.map(fn x -> {x[:line_count], "https://www.data.gouv.fr/fr/datasets/" <> x[:dataset_id]} end)
|> IO.inspect(limit: :infinity)

# Combien par "date de validation" breakdown ?
# Combien par "date de mise à jour" (théorique ???)
# Combien de PDC ça constitue ?
# Tout revalider moi-même et vérifier ? Oui. Oui. On aura des surprises.

Logger.info("Inserting report in DB...")

%DB.ProcessingReport{}
|> DB.ProcessingReport.changeset(%{content: %{resources: resources}})
|> DB.Repo.insert!()

IO.puts("Done")
