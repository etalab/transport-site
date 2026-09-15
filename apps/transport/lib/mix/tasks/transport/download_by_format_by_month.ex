defmodule Mix.Tasks.Transport.DownloadByFormatByMonth do
  @moduledoc """
  Download counts by format and month, exported as CSV.

  ## Usage

      mix Transport.DownloadByFormatByMonth [--output FILE]

  Defaults to printing to stdout. Use `--output` to write to a file.

  ## Example

      mix Transport.DownloadByFormatByMonth --output downloads.csv
  """

  use Mix.Task
  require Logger
  import Ecto.Query

  @relevant_formats [
    "csv",
    "gbfs",
    "geojson",
    "GTFS",
    "gtfs-rt",
    "html",
    "json",
    "NeTEx",
    "pdf",
    "SIRI",
    "SIRI Lite",
    "zip"
  ]

  @doc false
  def run(args) do
    Mix.Task.run("app.start")

    {opts, _, _} =
      OptionParser.parse(args, switches: [output: :string])

    rows = DB.Repo.all(query())

    csv =
      [{"format", "year_month", "sum"} | rows]
      |> Enum.map_join("\n", fn {f, y, s} -> Enum.join([f, y, to_string(s)], ",") end)

    csv_with_newline = csv <> "\n"

    case opts[:output] do
      nil ->
        IO.write(csv_with_newline)

      path ->
        File.write!(path, csv_with_newline)
        Logger.info("Wrote #{length(rows)} rows to #{path}")
    end
  end

  defp query do
    from(rmm in DB.ResourceMonthlyMetric,
      join: r in DB.Resource,
      on: r.datagouv_id == rmm.resource_datagouv_id,
      where:
        rmm.metric_name == :downloads and
          r.format in ^@relevant_formats,
      group_by: [r.format, rmm.year_month],
      order_by: [asc: r.format, asc: rmm.year_month],
      select: {r.format, rmm.year_month, sum(rmm.count)}
    )
  end
end
