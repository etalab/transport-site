# mix run scripts/irve/validate_and_summarize.exs

# Change me
file_path = "consolidation_transport_irve_statique.csv"

Transport.LogTimeTaken.log_time_taken("Validating #{file_path}", fn ->
  IO.puts("Starting validating downloaded copy of #{file_path}…")
  {summary, _validated_df} = File.read!(file_path) |> Transport.IRVE.Validator.validate_and_summarize()

  IO.inspect(summary, IEx.inspect_opts())
end)
