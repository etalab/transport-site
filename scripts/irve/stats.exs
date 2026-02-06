Mix.install([
  {:req, "~> 0.5.15"},
  {:explorer, "~> 0.11.0"}
])

sources = [
  {"https://proxy.transport.data.gouv.fr/resource/consolidation-transport-avec-doublons-irve-statique",
   "consolidation-transport-avec-doublons-irve-statique.csv", :resource_datagouv_id},
  {"https://proxy.transport.data.gouv.fr/resource/consolidation-nationale-irve-statique-brute-v1",
   "consolidation-nationale-irve-statique-brute-v1.csv", :original_resource_id},
  {"https://www.data.gouv.fr/fr/datasets/r/eb76d20a-8501-400e-b336-d85724de5435", "consolidation-data-gouv.csv",
   :datagouv_resource_id}
  # # generate with `mix run dump-simple-consolidation.exs`
  # {:on_disk, "simple-consolidation.csv", :datagouv_resource_id}
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

  def inspect(result, label \\ nil) do
    options =
      IEx.inspect_opts()
      |> Keyword.put(:label, label)
      |> Keyword.put(:width, 0)

    IO.inspect(result, options)
  end

  def get_resource_id_series({filename, column_atom}) do
    df = Explorer.DataFrame.from_csv!(filename, infer_schema_length: nil)
    column = Atom.to_string(column_atom)
    df[column]
  end

  def local_path(identifier), do: Path.join(__DIR__, "../../cache-dir/#{identifier}")

  def maybe_download(:on_disk, _local_path), do: nil
  def maybe_download(url, local_path), do: Stats.cached_download!(url, local_path)

  def compute_stats({url_or_atom, identifier, _resource_id_column}) do
    local_path = local_path(identifier)
    maybe_download(url_or_atom, local_path)

    Stats.compute(local_path)
    |> Map.put(:path, local_path |> Path.basename())
  end
end

sources
|> Enum.map(&Stats.compute_stats(&1))
|> Explorer.DataFrame.new()
|> Explorer.DataFrame.select([:path, :count, :distinct_count, :duplicates])
|> Explorer.DataFrame.print()
