# mix run scripts/irve/data-frame.exs
#
# LIMIT=5 mix run scripts/irve/data-frame.exs

limit = System.get_env("LIMIT") |> then(&if &1, do: String.to_integer(&1))

Transport.Jobs.IRVEConsolidationJob.perform(%Oban.Job{args: %{limit: limit}})

IO.puts("""
 ╔═════════════════════════╗
 ║     Done ! Oh Yeah.     ║
 ╚═════════════════════════╝
""")
