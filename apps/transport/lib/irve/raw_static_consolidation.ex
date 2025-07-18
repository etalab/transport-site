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
  # and another one (we'll create a more structured filter later)
  @air_france_klm_dataset_id "642167910d33a1a75ebfa1d2"

  @doc """
  Download content separately from processing, because we need to provide an estimate of the number of lines
  even if the processing fails. Asserting 200 is fine here, because the target server is data gouv & quite reliable.
  """
  @spec download_resource_content!(String.t()) :: map()
  def download_resource_content!(url) do
    %{status: status, body: body} = Transport.IRVE.Fetcher.get!(url, compressed: false, decode_body: false)
    %{status: status, body: body}
  end

  @doc """
  Process a row (resource). The full content (body) is expected together with the original file extension.
  """
  @spec process_resource(map(), binary(), integer(), String.t()) :: {:ok, Explorer.DataFrame.t()} | {:error, any()}
  def process_resource(row, body, status, extension) do
    if status != 200 do
      raise "HTTP status is not 200 (#{status})"
    end

    # A number of checks are carried out before attempting to parse the data, using a couple of heuristics,
    # in order to get meaningful error messages in the report.
    run_cheap_blocking_checks(body, extension)
    df = Transport.IRVE.Processing.read_as_data_frame(body)

    # add traceability information
    df =
      df
      |> Explorer.DataFrame.mutate(original_dataset_id: ^row.dataset_id)
      |> Explorer.DataFrame.mutate(original_resource_id: ^row.resource_id)

    log_debugging_stuff(row, df)
    {:ok, df}
  rescue
    error ->
      {:error, error}
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

    if !String.valid?(body) do
      raise("string is not valid UTF-8 (could be binary content, or latin1)")
    end
  end

  @doc """
  Not much used anymore, but has helped tremendously to debug x/y parsing issues,
  and I'm keeping the code here because I expect it to be useful again in the future.
  """
  def log_debugging_stuff(resource_id, df) do
    nil_counts = Explorer.DataFrame.nil_count(df)

    nil_counts = {
      Explorer.Series.at(nil_counts[:id_pdc_itinerance], 0),
      Explorer.Series.at(nil_counts[:x], 0),
      Explorer.Series.at(nil_counts[:y], 0)
    }

    unless nil_counts == {0, 0, 0} do
      Logger.warning("Resource #{resource_id} has nil on key data (#{nil_counts |> inspect})")
    end
  end

  def concat_rows(nil, df), do: df
  def concat_rows(main_df, df), do: Explorer.DataFrame.concat_rows(main_df, df)

  def exclude_irrelevant_resources(stream) do
    stream
    # exclude data gouv generated consolidation
    |> Enum.reject(fn r -> r.dataset_organisation_id == @datagouv_organization_id end)
    # also exclude "test dataset" https://www.data.gouv.fr/en/datasets/test-data-set
    # which is a large file marked as IRVE
    |> Enum.reject(fn r -> r.dataset_id == @test_dataset_id end)
    # and similarly: https://github.com/etalab/transport-site/issues/4660) 166MB file
    |> Enum.reject(fn r -> r.dataset_id == @air_france_klm_dataset_id end)
  end

  def build_report_item(row, body, extension, optional_error) do
    %Transport.IRVE.ReportItem{
      dataset_id: row.dataset_id,
      resource_id: row.resource_id,
      resource_url: row.url,
      error: optional_error,
      estimated_pdc_count: body |> String.split("\n") |> Enum.count(),
      extension: extension
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
        Logger.info("Processing resource #{row.resource_id} (url=#{row.url})")

        %{body: body, status: status} = download_resource_content!(row.url)
        extension = Path.extname(row.url)

        {main_df, optional_error} =
          case process_resource(row, body, status, extension) do
            {:ok, df} -> {concat_rows(main_df, df), nil}
            {:error, error} -> {main_df, error}
          end

        report_item = build_report_item(row, body, extension, optional_error)

        %{
          df: main_df,
          report: [report_item | report]
        }
      end)

    consolidation_filename = Keyword.fetch!(options, :data_file)
    Logger.info("Generating IRVE consolidation data file at #{consolidation_filename}")

    output.df
    |> Explorer.DataFrame.to_csv!(consolidation_filename)

    report_filename = Keyword.fetch!(options, :report_file)
    Logger.info("Generating IRVE consolidation report file at #{report_filename}")

    output.report
    |> Enum.reverse()
    |> Enum.map(&Map.from_struct/1)
    |> Enum.map(fn x -> Map.put(x, :error, x.error |> inspect) end)
    |> Explorer.DataFrame.new()
    |> Explorer.DataFrame.to_csv!(report_filename)
  end
end
