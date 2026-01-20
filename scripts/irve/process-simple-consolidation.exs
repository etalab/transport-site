# mix run scripts/irve/process-simple-consolidation.exs
# Options:
# --destination : values "local_disk" or "send_to_s3" (default: "send_to_s3")
# --erase-existing-data: values "all", "partial", or "none" (default: "none")
# --debug : if present, will print a summary of the report at the end and log each processed item
# Advised dev use:
# mix run scripts/irve/process-simple-consolidation.exs --destination local_disk --erase-existing-data all --debug

import Ecto.Query
Logger.configure(level: :info)
import Ecto.Query

{opts, _args} =
  OptionParser.parse!(System.argv(),
    strict: [erase_existing_data: :string, destination: :string, debug: :boolean]
  )

# Set default options in case of missing option (won’t override provided ones even invalid, but strict matching later)
opts =
  Keyword.validate!(opts,
    destination: "send_to_s3",
    erase_existing_data: "none",
    limit: if(limit = System.get_env("LIMIT"), do: String.to_integer(limit), else: nil)
    debug: false
  )

report_df = Transport.IRVE.SimpleConsolidation.process(options)

destination =
  if opts[:destination] in ["local_disk", "send_to_s3"] do
    String.to_atom(opts[:destination])
  else
    raise(ArgumentError, "Invalid destination option")
  end

IO.puts("Using destination: #{destination}")

# reusable function that we call before + after the processing
display_counts = fn ->
  IO.puts("Number of valid PDCs now in database: #{DB.IRVEValidPDC |> DB.Repo.aggregate(:count)}")
  unique_count = DB.Repo.one(from(p in DB.IRVEValidPDC, select: count(p.id_pdc_itinerance, :distinct)))
  IO.puts("Number of unique `id_pdc_itinerance` now in base: #{unique_count}")

  IO.puts("Number of valid files in database: #{DB.IRVEValidFile |> DB.Repo.aggregate(:count)}")
end

display_counts.()

case erase_existing_data do
  "all" ->
    IO.puts("Erasing all existing IRVE valid files and PDCs...")
    DB.Repo.delete_all(DB.IRVEValidFile)

  "partial" ->
    IO.puts("Erasing some existing IRVE valid files and PDCs…")

    DB.Repo.delete_all(
      from(f in DB.IRVEValidFile,
        where: f.id in subquery(from(f2 in DB.IRVEValidFile, select: f2.id, limit: 100))
      )
    )

  "none" ->
    IO.puts("Keeping existing data...")
end

report_df = Transport.IRVE.SimpleConsolidation.process(destination: destination, debug: debug)

if debug do
  report_df["status"]
  |> Explorer.Series.frequencies()
  |> IO.inspect(IEx.inspect_opts())
end

IO.puts("End of processing. Final counts:")

display_counts.()
