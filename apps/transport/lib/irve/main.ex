defmodule Transport.IRVE.Main do

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

  def download_and_parse_all(resources) do
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
  end

  def insert_report!(resources) do
    %DB.ProcessingReport{}
    |> DB.ProcessingReport.changeset(%{content: %{resources: resources}})
    |> DB.Repo.insert!()
  end
end
