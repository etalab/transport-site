Mix.install([
  {:req, "~> 0.5.15"},
  {:explorer, "~> 0.11.0"}
])

sources = [
  {"https://proxy.transport.data.gouv.fr/resource/consolidation-nationale-irve-statique", "consolidation-pan.csv"},
  {"https://www.data.gouv.fr/fr/datasets/r/eb76d20a-8501-400e-b336-d85724de5435", "consolidation-data-gouv.csv"}
]

defmodule Stats do
  require Explorer.DataFrame

  def compute(file) do
    df = Explorer.DataFrame.from_csv!(file, infer_schema_length: nil)

    count = df["id_pdc_itinerance"] |> Explorer.Series.size()
    distinct_count = df["id_pdc_itinerance"] |> Explorer.Series.distinct() |> Explorer.Series.size()
    duplicates = count - distinct_count

    %{
      count: count,
      distinct_count: distinct_count,
      duplicates: duplicates
    }
  end

  def cached_download!(url, file) do
    # IO.puts "#{url} : #{file}"
    # File.rm!(file)
    unless File.exists?(file) do
      %{status: 200} = Req.get!(url, into: File.stream!(file))
    end
  end

  def inspect(result, label) do
    options =
      IEx.inspect_opts()
      |> Keyword.put(:label, label)
      |> Keyword.put(:width, 0)

    IO.inspect(result, options)
  end
end

sources
|> Enum.each(fn {url, local_filename} ->
  file = Path.join(__DIR__, "../../cache-dir/#{local_filename}")
  Stats.cached_download!(url, file)
  Stats.inspect(Stats.compute(file), file |> Path.basename())
end)
