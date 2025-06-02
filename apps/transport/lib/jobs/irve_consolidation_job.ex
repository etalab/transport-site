defmodule Transport.Jobs.IRVEConsolidationJob do
  @moduledoc """
  Nightly production of IRVE consolidation.
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

        Transport.IRVE.Consolidation.build_aggregate_and_report!(config)

        upload_aggregate!(
          data_file,
          "irve_static_consolidation_#{timestamp()}.csv",
          "irve_static_consolidation_.csv"
        )
      end)
    end)
  end

  def build_filter(nil = _limit), do: nil
  def build_filter(limit) when is_integer(limit), do: fn stream -> stream |> Enum.take(limit) end
  def timestamp, do: DateTime.utc_now() |> Calendar.strftime("%Y%m%d.%H%M%S.%f")
end
