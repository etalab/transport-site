defmodule Transport.IRVE.Consolidation do
  require Logger
  import Transport.IRVE.Static.Probes

  @moduledoc """
  Static IRVE consolidation code.

  The code goes through the resources marked with format `etalab/schema-irve-statique`
  on data gouv, and attempts to create a consolidated output with the same format.
  """

  # FIXME: "continue but report" when meeting unexpected (e.g. HTTP) error
  # FIXME: clean-up code
  # FIXME: move hardcoding filtering (very useful for sampling etc) into caller code

  @doc """
  Download content separately from processing, because we need to provide an estimate of the number of lines
  even if the processing fails. Asserting 200 is fine here, because the target server is data gouv & quite reliable.
  """
  def download_resource_content!(url) do
    %{status: 200, body: body} = Transport.IRVE.Fetcher.get!(url, compressed: false, decode_body: false)
    body
  end

  @doc """
  Process a row (resource). The full content (body) is expected together with the original file extension.
  """
  def process_resource(row, body, extension) do
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
    # we only support comma at this point. NOTE: commas can be here too
    if header_separator == ";" do
      raise("unsupported column separator #{header_separator}")
    end

    if !String.valid?(body) do
      raise("string is not valid UTF-8 (could be binary content, or latin1)")
    end

    df = Transport.IRVE.Processing.read_as_data_frame(body)

    nil_counts = Explorer.DataFrame.nil_count(df)

    nil_counts = {
      Explorer.Series.at(nil_counts[:id_pdc_itinerance], 0),
      Explorer.Series.at(nil_counts[:x], 0),
      Explorer.Series.at(nil_counts[:y], 0)
    }

    unless nil_counts == {0, 0, 0} do
      Logger.warning("Resource #{row.resource_id} has nil on key data (#{nil_counts |> inspect})")
    end

    {:ok, df}
  rescue
    error ->
      {:error, error}
  end

  def concat_rows(nil, df), do: df
  def concat_rows(main_df, df), do: Explorer.DataFrame.concat_rows(main_df, df)

  @datagouv_organization_id "646b7187b50b2a93b1ae3d45"
  @test_dataset_id "67811b8e8934d388950bca3f"

  def exclude_irrelevant_resources(stream) do
    stream
    # exclude data gouv generated consolidation
    |> Enum.reject(fn r -> r.dataset_organisation_id == @datagouv_organization_id end)
    # also exclude "test dataset" https://www.data.gouv.fr/en/datasets/test-data-set
    # which is a large file marked as IRVE
    |> Enum.reject(fn r -> r.dataset_id == @test_dataset_id end)
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

  def build_aggregate_and_report! do
    output =
      Transport.IRVE.Extractor.datagouv_resources()
      |> exclude_irrelevant_resources()
      |> Enum.sort_by(fn r -> [r.dataset_id, r.resource_id] end)
      |> Enum.reduce(%{df: nil, report: []}, fn row, %{df: main_df, report: report} ->
        Logger.info("Processing resource #{row.resource_id}")

        body = download_resource_content!(row.url)
        extension = Path.extname(row.url)

        {main_df, optional_error} =
          case process_resource(row, body, extension) do
            {:ok, df} -> {concat_rows(main_df, df), nil}
            {:error, error} -> {main_df, error}
          end

        report_item = build_report_item(row, body, extension, optional_error)

        %{
          df: main_df,
          report: [report_item | report]
        }
      end)

    output_folder = Path.join(__DIR__, "../../data-tmp")
    if !File.exists?(output_folder), do: File.mkdir(output_folder)

    consolidation_filename = output_folder |> Path.join("irve-consolidation.csv") |> Path.expand()
    Logger.info("Generating #{consolidation_filename}")

    output.df
    |> Explorer.DataFrame.to_csv!(consolidation_filename)

    report_filename = output_folder |> Path.join("irve-report.csv") |> Path.expand()
    Logger.info("Generating #{report_filename}")

    output.report
    |> Enum.reverse()
    |> Enum.map(&Map.from_struct/1)
    |> Enum.map(fn x -> Map.put(x, :error, x.error |> inspect) end)
    |> Explorer.DataFrame.new()
    |> Explorer.DataFrame.to_csv!(report_filename)
  end
end
