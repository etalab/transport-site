# DataProfiling id_pdc_itinerance duplication in the dynamic IRVE consolidated feed.

Mix.install([
  {:req, "~> 0.5.15"},
  {:explorer, "~> 0.11.0"}
])

defmodule DataProfiling do
  require Explorer.DataFrame
  alias Explorer.{DataFrame, Series}

  @url "https://proxy.transport.data.gouv.fr/resource/consolidation-nationale-irve-dynamique?format=parquet&include_origin=1"
  @path Path.join(__DIR__, "../../cache-dir/consolidation-nationale-irve-dynamique.parquet")

  def run do
    IO.puts("# #{DateTime.utc_now() |> DateTime.to_iso8601()}")
    IO.puts("# #{@url}\n")
    File.mkdir_p!(Path.dirname(@path))
    unless File.exists?(@path), do: %{status: 200} = Req.get!(@url, into: File.stream!(@path))

    df = DataFrame.from_parquet!(@path)
    total = DataFrame.n_rows(df)
    distinct = df["id_pdc_itinerance"] |> Series.distinct() |> Series.size()
    IO.puts("rows=#{total}  distinct_pdc=#{distinct}  dup_rate=#{Float.round((total - distinct) / total * 100, 2)}%\n")

    df
    |> DataFrame.group_by("origin")
    |> DataFrame.summarise(rows: count(col("id_pdc_itinerance")), distinct_pdc: n_distinct(col("id_pdc_itinerance")))
    |> DataFrame.sort_by(desc: col("rows"))
    |> DataFrame.print(limit: :infinity)

    IO.puts("\nTop origin-set patterns (PDC partagé par plusieurs feeds) :")

    df
    |> DataFrame.select(["id_pdc_itinerance", "origin"])
    |> DataFrame.distinct()
    |> DataFrame.to_rows(atom_keys: true)
    |> Enum.group_by(_key = & &1.id_pdc_itinerance, _value = & &1.origin)
    |> Enum.map(fn {_pdc, origins} -> origins |> Enum.sort() |> Enum.join(" + ") end)
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_origin_set, count} -> count end, :desc)
    |> Enum.take(30)
    |> Enum.each(fn {origin_set, count} ->
      IO.puts("  #{String.pad_leading(to_string(count), 7)}  #{origin_set}")
    end)
  end
end

DataProfiling.run()
