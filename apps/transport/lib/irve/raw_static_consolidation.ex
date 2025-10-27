defmodule Transport.IRVE.RawStaticConsolidation do
  require Logger
  import Transport.IRVE.Static.Probes

  @moduledoc """
  Consolidates IRVE (Electric Vehicle Charging Infrastructure) data from multiple data gouv resources.

  This module processes resources marked with the
  [`etalab/schema-irve-statique`](https://schema.data.gouv.fr/etalab/schema-irve-statique/) format
  on data.gouv.fr and creates a unified, consolidated dataset following the same schema.

  It is named "raw" because:
  - It makes no attempt to dedupe charging points (if the same `id_pdc_itinerance`
    is twice or more in the resources, it will appear that number of times in the consolidation output)
  - It does not keep state between runs (e.g. no memory of previously seen files)

  ## Process Overview

  1. **Resources Discovery**: List IRVE resources via the data.gouv.fr API
  2. **Content Download**: Download each resource
  3. **Data Processing**: Attempt to parse CSV files, ensure basic typing compliance
  4. **Consolidation**: Combine all valid datasets into a single DataFrame
  5. **Report Generation**: Create detailed processing report for iterating on quality

  No attempt is made to parallelize processing at the moment.

  ## Error Handling

  Limitation: one HTTP error (non-200) will fail everything for now (this will be improved in the non-raw version).
  Other processing errors will be handled gracefully.

  ## Output Files

  - A consolidated CSV resource aggregating all the files that could be processed
  - A report CSV file listing all considered resources, with the outcome & error message
  """
  require Explorer.DataFrame

  # needed to filter out the existing, data-gouv provided consolidation
  @datagouv_organization_id "646b7187b50b2a93b1ae3d45"
  # similarly, required to eliminate a test file
  @test_dataset_id "67811b8e8934d388950bca3f"

  @doc """
  Store the content of a resource locally, returning a file stream and the HTTP status code.
  The file will have a name based on the resource ID which is good enough to prevent collisions.
  """

  @spec store_resource_content!(map()) :: map()
  def store_resource_content!(%{url: url, resource_id: resource_id}) do
    %{body: file_stream, status: status} =
      Transport.IRVE.Fetcher.get_and_store_file!(url, "irve_raw_#{resource_id}", compressed: false, decode_body: false)

    %{body: file_stream, status: status}
  end

  @doc """
  Process a row (resource). The full content (body) is expected together with the original file extension.
  """
  @spec process_resource(map(), binary(), integer(), String.t()) :: {:ok, Explorer.DataFrame.t()} | {:error, any()}
  def process_resource(row, file_stream, status, extension) do
    if status != 200 do
      raise "HTTP status is not 200 (#{status})"
    end

    body = File.read!(file_stream.path)

    # Producers can only be orgs, not individuals.
    # We perform the check here because we want an error to be reported and an estimation of number of pdc.
    # That needs the body to be downloaded even if the body isn’t used for the check.
    ensure_producer_is_org!(row)

    # A number of checks are carried out before attempting to parse the data, using a couple of heuristics,
    # in order to get meaningful error messages in the report.
    run_cheap_blocking_checks(body, extension)

    # We convert the rare latin-1 files into UTF-8
    body = ensure_utf8(body)

    # Convert a bogus column for specific cases, until it is fixed in the source
    body = maybe_rename_bogus_num_pdl(row.dataset_id, body)

    df = Transport.IRVE.Processing.read_as_data_frame(body)

    # add traceability information
    df =
      df
      |> Explorer.DataFrame.mutate(original_dataset_id: ^row.dataset_id)
      |> Explorer.DataFrame.mutate(original_resource_id: ^row.resource_id)

    log_debugging_stuff(row.resource_id, df)
    {:ok, df}
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Some data files have `num-pdl` instead of `num_pdl`. This is a quick-fix until it gets fixed.

  iex> maybe_rename_bogus_num_pdl("6853b993bb3e53379f17007c", "id_pdc_itinerance,num-pdl\\n123,456")
  "id_pdc_itinerance,num_pdl\\n123,456"
  """

  def maybe_rename_bogus_num_pdl(dataset_id, body)
      when dataset_id in ["65f1c621e07085a369aacc22", "6853b993bb3e53379f17007c"] do
    [headers, body] = String.split(body, "\n", parts: 2)
    headers = headers |> String.replace("num-pdl", "num_pdl")
    [headers, body] |> Enum.join("\n")
  end

  def maybe_rename_bogus_num_pdl(_, body), do: body

  @doc """
  Ensure that binary content is valid UTF-8. If not, attempt conversion from
  Latin-1 to UTF-8, assuming the original encoding is Latin-1.

  NOTE: This is not foolproof. The function does not verify that the input is
  actually Latin-1. Any byte sequence is technically valid Latin-1. However,
  based on our typical data sources (primarily French), this assumption allows
  us to recover and correctly convert over 100 additional resources.

  Example: already valid UTF-8 is returned unchanged.

      iex> Transport.IRVE.RawStaticConsolidation.ensure_utf8("valid utf8")
      "valid utf8"

  The byte `0xE9` represents "é" in Latin-1. The function converts it accordingly:

      iex> Transport.IRVE.RawStaticConsolidation.ensure_utf8(<<0xE9>>)
      "é"

  This function does not raise errors for any binary input. Only non-binary input
  (e.g., integers, maps) will raise an exception.
  """
  def ensure_utf8(body) do
    if String.valid?(body) do
      body
    else
      case :unicode.characters_to_binary(body, :latin1, :utf8) do
        converted when is_binary(converted) ->
          converted

        {:error, _, _} ->
          raise("error during latin 1 -> UTF-8 transcoding (should not happen)")

        {:incomplete, _, _} ->
          raise("string contains incomplete latin1 sequences")
      end
    end
  end

  def run_cheap_blocking_checks(body, extension) do
    if Transport.ZipProbe.likely_zip_content?(body) do
      raise("the content is likely to be a zip file, not uncompressed CSV data")
    end

    if (extension |> String.downcase()) not in ["", ".csv"] do
      raise("the content is likely not a CSV file (extension is #{extension})")
    end

    if probably_v1_schema(body) do
      raise("looks like a v1 irve")
    end

    if !has_id_pdc_itinerance(body) do
      raise("content has no id_pdc_itinerance in first line")
    end

    header_separator = hint_header_separator(body)

    unless header_separator in [";", ","] do
      raise("unsupported column separator #{header_separator}")
    end
  end

  def ensure_producer_is_org!(%{dataset_organisation_id: "???"}), do: raise("producer is not an organization")

  def ensure_producer_is_org!(_row), do: :ok

  @doc """
  Not much used anymore, but has helped tremendously to debug x/y parsing issues,
  and I'm keeping the code here because I expect it to be useful again in the future.
  """
  def log_debugging_stuff(resource_id, df) do
    nil_counts = Explorer.DataFrame.nil_count(df)

    nil_counts = {
      Explorer.Series.at(nil_counts[:id_pdc_itinerance], 0),
      Explorer.Series.at(nil_counts[:longitude], 0),
      Explorer.Series.at(nil_counts[:latitude], 0)
    }

    unless nil_counts == {0, 0, 0} do
      Logger.warning("Resource #{resource_id} has nil on key data (#{nil_counts |> inspect})")
    end
  end

  def maybe_concat_rows({:error, error}, main_df), do: {main_df, error}
  def maybe_concat_rows({:ok, df}, nil), do: {df, nil}
  def maybe_concat_rows({:ok, df}, main_df), do: {Explorer.DataFrame.concat_rows(main_df, df), nil}

  def exclude_irrelevant_resources(stream) do
    stream
    # exclude data gouv generated consolidation
    |> Enum.reject(fn r -> r.dataset_organisation_id == @datagouv_organization_id end)
    # also exclude "test dataset" https://www.data.gouv.fr/en/datasets/test-data-set
    # which is a large file marked as IRVE
    |> Enum.reject(fn r -> r.dataset_id == @test_dataset_id end)
  end

  def build_report_item(row, file_stream, extension, optional_error) do
    %Transport.IRVE.ReportItem{
      dataset_id: row.dataset_id,
      resource_id: row.resource_id,
      resource_url: row.url,
      error: optional_error,
      estimated_pdc_count: file_stream |> Enum.count(),
      extension: extension,
      local_file_path: file_stream.path
    }
  end

  def maybe_filter(stream, nil), do: stream
  def maybe_filter(stream, function) when is_function(function), do: stream |> function.()

  @doc """
  Core method. Builds a consolidated IRVE dataset and generates a processing report.
  Fetches IRVE resources from data.gouv.fr, processes each resource, and
  consolidates the data into a single CSV file. Also generates a detailed
  report of the processing results.

  ### Options

  - `:data_file` (required) - Path where to generate the consolidated CSV containing all successfully processed IRVE data
  - `:report_file` (required) - Path where the consolidation report (CSV) will be generated, containing metadata and errors for each processed resource
  - `:filter` (optional) - Filter to apply to resources before processing (useful for e.g. sampling)
  """
  def build_aggregate_and_report!(options \\ []) do
    output =
      Transport.IRVE.Extractor.datagouv_resources()
      |> exclude_irrelevant_resources()
      |> maybe_filter(options[:filter])
      |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
      |> Enum.reduce(%{df: nil, report: []}, fn row, %{df: main_df, report: report} ->
        process_individual_resource_and_report(row, main_df, report)
      end)

    consolidation_filename = Keyword.fetch!(options, :data_file)
    Logger.info("Generating IRVE consolidation data file at #{consolidation_filename}")

    output.df
    |> Explorer.DataFrame.to_csv!(consolidation_filename)

    report_filename = Keyword.fetch!(options, :report_file)
    Logger.info("Generating IRVE consolidation report file at #{report_filename}")

    report =
      output.report
      |> Enum.reverse()

    report
    |> Enum.map(&Map.from_struct/1)
    |> Enum.map(fn x -> Map.put(x, :error, x.error |> inspect) end)
    |> Explorer.DataFrame.new()
    |> Explorer.DataFrame.to_csv!(report_filename)

    report
  end

  def process_individual_resource_and_report(row, main_df, report) do
    Logger.info("Processing resource #{row.resource_id} (url=#{row.url}, dataset_id=#{row.dataset_id})")
    %{body: file_stream, status: status} = store_resource_content!(row)
    extension = Path.extname(row.url)

    {main_df, optional_error} = process_resource(row, file_stream, status, extension) |> maybe_concat_rows(main_df)

    report_item = build_report_item(row, file_stream, extension, optional_error)

    %{
      df: main_df,
      report: [report_item | report]
    }
  end
end
