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

  @doc """
  Fetches the list of all `schema-irve-statique` resources from data gouv, using parallelized pagination.

  The code fetches datasets, then unpack resources belonging to each dataset.
  """
  def resources(pagination_options \\ []) do
    @static_irve_datagouv_url
    |> Transport.IRVE.Fetcher.pages(pagination_options)
    |> Task.async_stream(&process_data_gouv_page/1, on_timeout: :kill_task, max_concurrency: 10)
    |> Stream.map(fn {:ok, result} -> result end)
    |> Stream.flat_map(fn page -> page[:data]["data"] end)
    |> Stream.map(&unpack_resources/1)
    |> Stream.concat()
    |> Stream.map(&remap_fields/1)
    |> Stream.filter(fn x -> x[:schema_name] == "etalab/schema-irve-statique" end)
    |> Enum.into([])
  end

  @doc """
  Retrieve one page of resource results from data gouv.
  """
  def process_data_gouv_page(%{url: url} = page) do
    Logger.info("Fetching data gouv page #{url}")
    %{status: 200, body: result} = Transport.IRVE.Fetcher.get!(url)
    Map.put(page, :data, result)
  end

  @doc """
  A quick imitation of `get_in` but raising error in case one of the keys is missing
  """
  def fetch_in!(list, [key]), do: Map.fetch!(list, key)
  def fetch_in!(list, [key | keys]), do: fetch_in!(Map.fetch!(list, key), keys)

  @doc """
  Return all resources for a given dataset, keeping a bit of dataset information around.
  """
  def unpack_resources(dataset) do
    dataset["resources"]
    |> Enum.map(fn x ->
      x
      |> Map.put(:dataset_id, fetch_in!(dataset, ["id"]))
      |> Map.put(:dataset_title, fetch_in!(dataset, ["title"]))
      |> Map.put(:dataset_organisation_name, get_in(dataset, ["organization", "name"]) || "???")
      |> Map.put(:dataset_organisation_url, get_in(dataset, ["organization", "page"]) || "???")
    end)
  end

  @doc """
  Extract resource fields we want to use.
  """
  def remap_fields(resource) do
    # using mandatory `fetch_in!` wherever I could, but `get_in` when occurrences
    # showed missing data
    %{
      resource_id: fetch_in!(resource, ["id"]),
      resource_title: fetch_in!(resource, ["title"]),
      dataset_id: fetch_in!(resource, [:dataset_id]),
      dataset_title: fetch_in!(resource, [:dataset_title]),
      dataset_organisation_name: fetch_in!(resource, [:dataset_organisation_name]),
      dataset_organisation_url: fetch_in!(resource, [:dataset_organisation_url]),
      valid: get_in(resource, ["extras", "validation-report:valid_resource"]),
      validation_date: get_in(resource, ["extras", "validation-report:validation_date"]),
      schema_name: get_in(resource, ["schema", "name"]),
      schema_version: get_in(resource, ["schema", "version"]),
      filetype: fetch_in!(resource, ["filetype"]),
      last_modified: fetch_in!(resource, ["last_modified"]),
      # vs latest?
      url: fetch_in!(resource, ["url"])
    }
  end

  @doc """
  Parallel-download & prepare a large list of resources.

  The optional callback helps updating the UI, if any.
  """
  def download_and_parse_all(resources, progress_callback \\ nil, download_options \\ []) do
    r = resources
    count = r |> length()

    r
    |> Enum.with_index()
    |> Task.async_stream(
      fn {row, index} ->
        if progress_callback, do: progress_callback.(index)

        log_time_taken("IRVE - processing #{index} over #{count} (#{row[:url]})", fn ->
          download_and_parse_one(row, index, download_options)
        end)
      end,
      timeout: 100_000,
      on_timeout: :kill_task,
      # Going higher will work, but there is a risk that data gouv rate-limiter & throttling
      # will kick-in, impacting other processes from our same IP address
      max_concurrency: 10
    )
    |> Enum.map(fn {:ok, x} -> x end)
    |> Enum.map(fn x ->
      Map.take(x, [
        :dataset_id,
        :dataset_title,
        :dataset_organisation_name,
        :dataset_organisation_url,
        :resource_id,
        :resource_title,
        :valid,
        :line_count,
        :filetype,
        :last_modified,
        :index,
        :raw_body
      ])
    end)
  end

  @doc """
  Download a given resource, keep HTTP status around, and extract some metadata.
  """
  def download_and_parse_one(row, index, options \\ []) do
    keep_the_body_around = options[:keep_the_body_around] || false

    %Req.Response{status: status, body: body} =
      Transport.IRVE.Fetcher.get!(row[:url], compressed: false, decode_body: false)

    row
    |> Map.put(:status, status)
    |> Map.put(:index, index)
    |> then(fn x -> process_resource_body(x, body) end)
    |> map_put_if(:raw_body, body, keep_the_body_around)
  end

  def map_put_if(map, _key, _value, false), do: map
  def map_put_if(map, key, value, true), do: Map.put(map, key, value)

  @doc """
  For a given resource and corresponding body, enrich data with
  extra stuff like estimated number of charge points.
  """
  def process_resource_body(%{status: 200} = row, body) do
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

  @doc """
  Save the outcome in the database for reporting.
  """
  def insert_report!(resources) do
    %DB.ProcessingReport{}
    |> DB.ProcessingReport.changeset(%{content: %{resources: resources}})
    |> DB.Repo.insert!()
  end
end
