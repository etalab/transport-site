Mix.install([
  {:req, "~> 0.5.15"},
  {:explorer, "~> 0.11.0"}
])

url = "https://proxy.transport.data.gouv.fr/resource/consolidation-nationale-irve-statique"
file = Path.join(__DIR__, "../../cache-dir/consolidation-nationale-irve-statique.csv")

# File.rm!(file)

unless File.exists?(file) do
  %{status: 200} = Req.get!(url, into: File.stream!(file))
end

defmodule Stats do
  require Explorer.DataFrame

  def compute(file) do
    df = Explorer.DataFrame.from_csv!(file, infer_schema_length: nil)

    %{
      count: df["id_pdc_itinerance"] |> Explorer.Series.size(),
      distinct_count: df["id_pdc_itinerance"] |> Explorer.Series.distinct() |> Explorer.Series.size()
    }
  end
end

IO.inspect(Stats.compute(file), IEx.inspect_opts())
