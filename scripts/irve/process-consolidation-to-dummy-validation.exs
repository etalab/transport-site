# mix run scripts/irve/process-consolidation-to-dummy-validation.exs
#
# LIMIT=5 mix run scripts/irve/process-consolidation-to-dummy-validation.exs

defmodule Transport.Jobs.IRVEConsolidationDummyValidationJob do
  @moduledoc """
  This dummy module is just a copy of `IRVEConsolidationJob` that adds a call to a dummy validation
  step after the consolidation is done.
  """
  use Oban.Worker, unique: [period: {1, :days}], tags: ["irve"], max_attempts: 3
  require Logger
  import Transport.S3.AggregatesUploader

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    with_tmp_file(fn data_file ->
      with_tmp_file(fn report_file ->
        config = [
          filter: build_filter(args[:limit]),
          data_file: data_file,
          report_file: report_file
        ]

        report = Transport.IRVE.RawStaticConsolidation.build_aggregate_and_report!(config)

        now = timestamp()

        upload_aggregate!(
          data_file,
          "irve_static_consolidation_#{now}.csv",
          "irve_static_consolidation.csv"
        )

        upload_aggregate!(
          report_file,
          "irve_static_consolidation_report_#{now}.csv",
          "irve_static_consolidation_report.csv"
        )

        # This is the added step:
        IRVEDummyValidation.perform_validation!(report)
        cleanup_tmp_resource_files(report)
      end)
    end)
  end

  def build_filter(nil = _limit), do: nil
  def build_filter(limit) when is_integer(limit), do: fn stream -> stream |> Enum.take(limit) end
  def timestamp, do: DateTime.utc_now() |> Calendar.strftime("%Y%m%d.%H%M%S.%f")

  @doc """
  Cleans up temporary resource files created during the raw consolidation generation.
  For now, these files are useless (during and after this raw consolidation) but later on they’ll be useful.
  """
  def cleanup_tmp_resource_files(report) do
    Enum.each(report, fn report_item -> File.rm!(report_item.local_file_path) end)
  end
end

defmodule IRVEDummyValidation do
  require Logger

  def perform_validation!(report) do
    resources_to_validate =
      report
      |> Enum.reject(fn row -> row.error end)

    Logger.info("Total resources fetched on datagouv: #{length(report)}")
    Logger.info("Total resources to validate: #{length(resources_to_validate)}")

    resources_to_validate |> Enum.each(&validate_resource!/1)
  end

  def validate_resource!(resource_report) do
    Logger.info("Validating resource #{resource_report.resource_id}")
    # Here would be the actual validation logic
    # Just showing that we can read the local file:
    Explorer.DataFrame.from_csv!(resource_report.local_file_path) |> IO.inspect()

    :ok
  end
end

limit = System.get_env("LIMIT") |> then(&if &1, do: String.to_integer(&1))

Transport.Jobs.IRVEConsolidationDummyValidationJob.perform(%Oban.Job{args: %{limit: limit}})

IO.puts("""
 ╔═════════════════════════╗
 ║     Done ! Oh Yeah.     ║
 ╚═════════════════════════╝
""")
