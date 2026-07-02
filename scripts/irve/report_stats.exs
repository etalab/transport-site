# Stats over an IRVE consolidation report CSV.
# Usage: mix run scripts/irve/report_stats.exs [path]
#   path defaults to consolidation_transport_irve_statique_rapport.csv
# Fully written by Claude Code, may be erased later.

require Explorer.DataFrame, as: DF
alias Explorer.Series

path = List.first(System.argv()) || "consolidation_transport_irve_statique_rapport.csv"

# Collapse the variable parts of an error message so similar errors group together.
normalize = fn
  nil ->
    nil

  "" ->
    nil

  msg ->
    msg
    # keep only the first line (some messages dump a long column list afterwards)
    |> String.split("\n")
    |> hd()
    |> String.replace(~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/, "…")
    |> String.replace(~r/The available columns are:.*/, "The available columns are: …")
    |> String.replace(~r/frequencies:.*/, "frequencies: …)")
    |> String.replace(~r/"[^"]*"/, ~S("…"))
    |> String.replace(~r/extension is [^)]+/, "extension is …")
    |> String.replace(~r/column separator .+/, "column separator …")
end

df = DF.from_csv!(path)
total = DF.n_rows(df)
total_pdc = df["estimated_pdc_count"] |> Series.sum()

category = df["error_message"] |> Series.to_list() |> Enum.map(normalize)
df = DF.put(df, "error_category", Series.from_list(category))

summarize = fn group_cols ->
  df
  |> DF.group_by(group_cols)
  |> DF.summarise(count: count(resource_id), pdc: sum(estimated_pdc_count))
  |> DF.sort_by(desc: count)
  |> DF.to_rows()
end

pct = fn n -> :erlang.float_to_binary(n / total * 100, decimals: 1) end

print = fn rows, key_cols ->
  for row <- rows do
    keys = key_cols |> Enum.map(&to_string(row[&1] || "—")) |> Enum.join(" / ")
    count = row["count"]
    pdc = row["pdc"] || 0

    IO.puts(
      "  #{String.pad_leading(to_string(count), 5)}  #{String.pad_leading(pct.(count) <> "%", 6)}  " <>
        "pdc=#{String.pad_leading(to_string(pdc), 8)}   #{keys}"
    )
  end
end

IO.puts("File: #{path}")
IO.puts("Total resources: #{total}    Total estimated PDC: #{total_pdc}\n")

IO.puts("== By status ==")
print.(summarize.(["status"]), ["status"])

IO.puts("\n== By status × error_type (exceptions in error_occurred) ==")

summarize.(["status", "error_type"])
|> Enum.reject(&is_nil(&1["error_type"]))
|> print.(["status", "error_type"])

IO.puts("\n== By status × error (normalized message) ==")

summarize.(["status", "error_category"])
|> Enum.reject(&is_nil(&1["error_category"]))
|> print.(["status", "error_category"])

IO.puts("\n== error_occurred by HTTP status ==")

df
|> DF.filter(status == "error_occurred")
|> DF.pull("error_message")
|> Series.to_list()
|> Enum.map(fn msg ->
  case Regex.run(~r/http_status=(\d+)/, msg || "") do
    [_, code] -> "http_status=#{code}"
    nil -> "non-http error"
  end
end)
|> Enum.frequencies()
|> Enum.sort_by(fn {_k, v} -> -v end)
|> Enum.each(fn {k, v} ->
  IO.puts("  #{String.pad_leading(to_string(v), 5)}  #{String.pad_leading(pct.(v) <> "%", 6)}  #{k}")
end)
