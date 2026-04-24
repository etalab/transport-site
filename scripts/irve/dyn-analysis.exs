Mix.install([
  {:req, "~> 0.5.15"},
  {:explorer, "~> 0.11.0"},
  {:yaml_elixir, "~> 2.12"}
])

path = Path.join(__DIR__, "../../../transport-proxy-config/proxy-config.yml") |> Path.expand()

path
|> YamlElixir.read_from_file!()
|> Map.fetch!("feeds")
|> Enum.filter(&(&1["identifier"] == "consolidation-nationale-irve-dynamique"))
|> then(fn [config] -> config end)
|> Map.fetch!("feeds")
|> Enum.each(fn %{"identifier" => id, "slug" => slug, "target_url" => url} ->
  IO.puts(slug)

  options = %{
    "input" => "url",
    "schema_name" => "schema-datagouvfr.etalab/schema-irve-dynamique",
    "url" => url
  }

  validata_url = "https://validata.fr/table-schema?" <> URI.encode_query(options)
  IO.puts(validata_url)

  #  IO.puts "https://validata.fr/table-schema?input=url&schema_name=schema-datagouvfr.etalab%2Fschema-irve-dynamique&schema_ref=&url=https%3A%2F%2Fwww.data.gouv.fr%2Fapi%2F1%2Fdatasets%2Fr%2F411443b1-6667-473f-8217-1c57c167408f"
end)
