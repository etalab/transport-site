Logger.configure(level: :info)

outcome =
  Transport.Jobs.GTFSImportStopsJob.refresh_all()
  |> IO.inspect(IEx.inspect_opts())

# Next steps:
# - count errors
# - report errors in aggregated fashion
