# mix run scripts/irve/process-simple-consolidation.exs
# Options:
# --destination : values "local_disk" or "send_to_s3" (default: "send_to_s3")
# --erase-existing-data: values "all", "partial", or "none" (default: "none")
# --debug : if present, will print a summary of the report at the end and log each processed item
# Advised dev use:
# mix run scripts/irve/process-simple-consolidation.exs --destination local_disk --erase_existing_data all --debug

import Ecto.Query
Logger.configure(level: :info)

{opts, _args, _} =
  OptionParser.parse(System.argv(),
    strict: [erase_existing_data: :string, debug: :boolean]
  )

destination =
  case opts[:destination] do
    "local_disk" -> :local_disk
    _ -> :send_to_s3
  end

erase_existing_data =
  case opts[:erase_existing_data] do
    "all" -> :all
    "partial" -> :partial
    _ -> :none
  end

debug = opts[:debug]

IO.puts("Number of valid PDCs in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")

IO.puts(
  "Number of distinct id_pdc_itinerance in these PDCs: #{DB.Repo.one(from(p in DB.IRVEValidPDC, select: count(p.id_pdc_itinerance, :distinct)))}"
)

IO.puts("Number of valid files in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")

IO.puts("Using destination: #{destination}")

case erase_existing_data do
  :all ->
    IO.puts("Erasing all existing IRVE valid files and PDCs...")
    DB.Repo.delete_all(DB.IRVEValidFile)

  :partial ->
    IO.puts("Erasing some existing IRVE valid files and PDCs…")

    DB.Repo.delete_all(
      from(f in DB.IRVEValidFile,
        where: f.id in subquery(from(f2 in DB.IRVEValidFile, select: f2.id, limit: 100))
      )
    )

  :none ->
    IO.puts("Keeping existing data...")
end

report_df = Transport.IRVE.SimpleConsolidation.process(destination: destination, debug: debug)

if debug do
  report_df["status"]
  |> Explorer.Series.frequencies()
  |> IO.inspect(IEx.inspect_opts())
end

IO.puts("Number of valid PDCs now in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")

IO.puts(
  "Number of distinct id_pdc_itinerance in these PDCs: #{DB.Repo.one(from(p in DB.IRVEValidPDC, select: count(p.id_pdc_itinerance, :distinct)))}"
)

IO.puts("Number of valid files now in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")
