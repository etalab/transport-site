# Transport.Jobs.IRVEConsolidationJob.perform(%Oban.Job{})

filter = fn(stream) -> 
  stream
  |> Enum.take(1)
end

Transport.IRVE.Consolidation.build_aggregate_and_report!(filter: filter)

IO.puts("""
 ╔═════════════════════════╗
 ║     Done ! Oh Yeah.     ║
 ╚═════════════════════════╝
""")
