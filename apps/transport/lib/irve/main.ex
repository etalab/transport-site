defmodule Transport.IRVE.Main do
  # Kept here for reference (we may want to fish datasets out of them later)
  # Some of them are completely outdated, but I'd rather keep the history here anyway.
  @other_urls [
    "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve",
    "https://www.data.gouv.fr/api/1/datasets/?tag=irve",
    "https://www.data.gouv.fr/api/1/datasets/?q=irve",
    "https://www.data.gouv.fr/api/1/datasets/?q=recharge+véhicules+électriques"
  ]

  @static_irve_datagouv_url "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique"

  def resources do
    @static_irve_datagouv_url
    |> Transport.IRVE.Streamer.pages()
    |> Stream.map(fn %{url: url} = page ->
      %{status: 200, body: result} = Transport.IRVE.Streamer.get!(url)
      Map.put(page, :data, result)
    end)
    |> Stream.flat_map(fn page -> page[:data]["data"] end)
    |> Stream.map(fn dataset ->
      dataset["resources"]
      |> Enum.map(fn x -> Map.put(x, :dataset_id, dataset["id"]) end)
    end)
    |> Stream.concat()
    |> Stream.map(fn x ->
      %{
        id: get_in(x, ["id"]),
        dataset_id: get_in(x, [:dataset_id]),
        valid: get_in(x, ["extras", "validation-report:valid_resource"]),
        validation_date: get_in(x, ["extras", "validation-report:validation_date"]),
        schema_name: get_in(x, ["schema", "name"]),
        schema_version: get_in(x, ["schema", "version"]),
        filetype: get_in(x, ["filetype"]),
        last_modified: get_in(x, ["last_modified"]),
        # vs latest?
        url: get_in(x, ["url"])
      }
    end)
    |> Stream.filter(fn x -> x[:schema_name] == "etalab/schema-irve-statique" end)
  end
end
