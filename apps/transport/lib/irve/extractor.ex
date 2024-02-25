defmodule Transport.IRVE.Extractor do
  @moduledoc """
  Higher level module responsible for the overall ETL work:
  - stream of data gouv IRVE resources meta-data
  - extra data added thanks to individual resource body fetching
  - report structure and insertion in database
  """

  require Logger
  import Transport.LogTimeTaken

  @static_irve_datagouv_url "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique"

  def resources do
    @static_irve_datagouv_url
    |> Transport.IRVE.Fetcher.pages()
    |> Task.async_stream(&process_data_gouv_page/1, on_timeout: :kill_task, max_concurrency: 10)
    |> Stream.map(fn {:ok, result} -> result end)
    |> Stream.flat_map(fn page -> page[:data]["data"] end)
    |> Stream.map(&unpack_resources/1)
    |> Stream.concat()
    |> Stream.map(&remap_fields/1)
    |> Stream.filter(fn x -> x[:schema_name] == "etalab/schema-irve-statique" end)
    |> Enum.into([])
  end

  def process_data_gouv_page(%{url: url} = page) do
    Logger.info("Fetching data gouv page #{url}")
    %{status: 200, body: result} = Transport.IRVE.Fetcher.get!(url)
    Map.put(page, :data, result)
  end

  def unpack_resources(dataset) do
    dataset["resources"]
    |> Enum.map(fn x ->
      x
      |> Map.put(:dataset_id, dataset["id"])
      |> Map.put(:dataset_title, dataset["title"])
    end)
  end

  def remap_fields(row) do
    %{
      resource_id: get_in(row, ["id"]),
      resource_title: get_in(row, ["title"]),
      dataset_id: get_in(row, [:dataset_id]),
      dataset_title: get_in(row, [:dataset_title]),
      valid: get_in(row, ["erowtras", "validation-report:valid_resource"]),
      validation_date: get_in(row, ["erowtras", "validation-report:validation_date"]),
      schema_name: get_in(row, ["schema", "name"]),
      schema_version: get_in(row, ["schema", "version"]),
      filetype: get_in(row, ["filetype"]),
      last_modified: get_in(row, ["last_modified"]),
      # vs latest?
      url: get_in(row, ["url"])
    }
  end

  def download_and_parse_all(resources, progress_callback \\ nil) do
    r = resources
    count = r |> length()

    r
    |> Enum.with_index()
    |> Task.async_stream(
      fn {row, index} ->
        if progress_callback, do: progress_callback.(index)

        log_time_taken("IRVE - processing #{index} over #{count} (#{row[:url]})", fn ->
          download_and_parse_one(row, index)
        end)
      end,
      timeout: 100_000,
      on_timeout: :kill_task,
      max_concurrency: 25
    )
    |> Enum.map(fn {:ok, x} -> x end)
    |> Enum.map(fn x ->
      Map.take(x, [:dataset_id, :dataset_title, :resource_id, :resource_title, :valid, :line_count, :index])
    end)
  end

  def download_and_parse_one(row, index) do
    %{status: status, body: body} =
      Transport.IRVE.Fetcher.get!(row[:url], compressed: false, decode_body: false)

    row
    |> Map.put(:status, status)
    |> Map.put(:index, index)
    |> then(fn x -> process_body(x, body) end)
  end

  def process_body(%{status: 200} = row, body) do
    body = body |> String.split("\n")
    first_line = body |> hd()
    line_count = (body |> length) - 1
    id_detected = first_line |> String.contains?("id_pdc_itinerance")
    # a field from v1, which does not end like a field in v2
    old_schema = first_line |> String.contains?("ad_station")

    row
    |> Map.put(:id_pdc_itinerance_detected, id_detected)
    |> Map.put(:old_schema, old_schema)
    |> Map.put(:first_line, first_line)
    |> Map.put(:line_count, line_count)
  end

  def process_body(row), do: row

  def insert_report!(resources) do
    %DB.ProcessingReport{}
    |> DB.ProcessingReport.changeset(%{content: %{resources: resources}})
    |> DB.Repo.insert!()
  end
end
