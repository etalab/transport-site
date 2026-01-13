# script to dump `DB.IRVEValidPDC` table into a local CSV
# (then you can use `stats.exs` to include it into the comparison with previous consolidations)
import Ecto.Query

fields =
  Transport.IRVE.StaticIRVESchema.field_names_list()
  |> Enum.reject(&(&1 == "coordonneesXY"))
  |> Enum.concat(["longitude", "latitude"])
  |> Enum.map(&String.to_atom/1)

stream = DB.IRVEValidPDC |> select([p], map(p, ^fields)) |> DB.Repo.stream()

{:ok, df} =
  DB.Repo.transact(fn ->
    result =
      stream
      |> Enum.into([])
      |> Explorer.DataFrame.new()

    {:ok, result}
  end)

IO.inspect(df, IEx.inspect_opts())

target = Path.join(__DIR__, "../../cache-dir/simple-consolidation.csv")

IO.puts("Saving to #{target}")
Explorer.DataFrame.to_csv!(df, target)
