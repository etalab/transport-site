#! /usr/bin/env mix run

# the basis of a mass-analysis script for IRVE files,
# inspired by https://github.com/etalab/notebooks/blob/master/irve-v2/consolidation-irve-v2.ipynb

require Logger

Logger.info("Retrieving each relevant datagouv page & listing resources")

resources = Transport.IRVE.Extractor.datagouv_resources()

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

resources = Transport.IRVE.Extractor.download_and_parse_all(resources)

Logger.info("Inserting report in DB...")

Transport.IRVE.Extractor.insert_report!(resources)

Logger.info("Doing more stats...")

resources
# |> Enum.filter(fn x -> x[:id_pdc_itinerance_detected] == true && x[:old_schema] == true end)
|> Enum.frequencies_by(fn x -> Map.take(x, [:id_pdc_itinerance_detected, :old_schema]) end)
|> IO.inspect()

recent_stuff =
  resources
  |> Enum.filter(fn x -> x[:id_pdc_itinerance_detected] end)

recent_stuff
|> Enum.frequencies_by(fn x -> x[:valid] end)
|> IO.inspect(IEx.inspect_opts() |> Keyword.put(:label, "group_by(:valid)"))

recent_stuff
|> Enum.filter(fn x -> x[:valid] == false end)
|> Enum.sort_by(fn x -> -x[:line_count] end)
|> Enum.map(fn x -> {x[:line_count], "https://www.data.gouv.fr/fr/datasets/" <> x[:dataset_id]} end)
|> IO.inspect(limit: :infinity)

IO.puts("Done")
