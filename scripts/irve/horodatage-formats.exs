Mix.install([
  {:req, "~> 0.5.15"},
  {:explorer, "~> 0.11.0"}
])

defmodule HorodatageAnalysis do
  require Explorer.DataFrame
  alias Explorer.{DataFrame, Series}

  def run do
    url = "http://proxy.localhost:5000/resource/consolidation-nationale-irve-dynamique?include_origin=1"

    IO.puts("Fetching consolidated feed...")
    %{status: 200, body: body} = Req.get!(url, decode_body: false)

    df = DataFrame.load_csv!(body, infer_schema_length: 0)
    IO.puts("#{DataFrame.n_rows(df)} rows loaded\n")

    patterns =
      df["horodatage"]
      |> Series.to_list()
      |> Enum.map(fn s -> String.replace(s, ~r/\d/, "D") end)
      |> Series.from_list()

    df = DataFrame.put(df, "pattern", patterns)

    IO.puts("=== Counts by origin + pattern ===\n")

    df
    |> DataFrame.group_by(["origin", "pattern"])
    |> DataFrame.summarise(count: count(col("id_pdc_itinerance")))
    |> DataFrame.sort_by([asc: col("origin"), desc: col("count")])
    |> DataFrame.print(limit: :infinity)

    IO.puts("\n=== One example per pattern ===\n")

    df
    |> DataFrame.distinct(["pattern"], keep_all: true)
    |> DataFrame.select(["origin", "pattern", "horodatage"])
    |> DataFrame.sort_by(asc: col("origin"))
    |> DataFrame.print(limit: :infinity)
  end
end

HorodatageAnalysis.run()
