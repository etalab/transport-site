# mix run scripts/irve/process-raw-static-consolidation.exs
#
# LIMIT=5 mix run scripts/irve/process-raw-static-consolidation.exs

limit = System.get_env("LIMIT") |> then(&if &1, do: String.to_integer(&1))

Transport.Jobs.IRVERawConsolidationJob.perform(%Oban.Job{args: %{limit: limit}})

IO.puts("""
 ╔═════════════════════════╗
 ║     Done ! Oh Yeah.     ║
 ╚═════════════════════════╝
""")
