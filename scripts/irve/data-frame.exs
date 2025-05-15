if true do
  Transport.Jobs.IRVEConsolidationJob.perform(%Oban.Job{args: %{limit: 1}})
else
  filter = fn stream ->
    stream
    |> Enum.take(1)
  end

  Transport.IRVE.Consolidation.build_aggregate_and_report!(filter: filter)
end

IO.puts("""
 ╔═════════════════════════╗
 ║     Done ! Oh Yeah.     ║
 ╚═════════════════════════╝
""")
