defmodule Transport.IRVE.V3.FieldChecksTest do
  use ExUnit.Case, async: true
  alias Explorer.{DataFrame, Series}

  alias Transport.IRVE.V3.{
    DynamicFixtureGenerator,
    FieldChecks,
    StaticFixtureGenerator,
    TarifsFixtureGenerator
  }

  @files %{
    statique: {StaticFixtureGenerator, "schema-irve-statique-v3.json"},
    dynamique: {DynamicFixtureGenerator, "schema-irve-dynamique-v3.json"},
    tarifs: {TarifsFixtureGenerator, "schema-irve-tarifs-v3.json"}
  }

  # Valid rows for the 3 files, consistent with each other.
  defp valid_rows do
    statique = StaticFixtureGenerator.generate(seed: 7, stations: 20, networks: 3)

    %{
      statique: statique,
      dynamique: DynamicFixtureGenerator.generate(statique),
      tarifs: TarifsFixtureGenerator.generate(statique)
    }
  end

  # Sets `field` to `value` on the first row.
  defp put_first(rows, field, value), do: List.update_at(rows, 0, &%{&1 | field => value})

  defp checks(rows, role) do
    {generator, schema_file} = @files[role]
    df = rows |> generator.to_csv() |> DataFrame.load_csv!(infer_schema_length: 0)
    df |> FieldChecks.run(Transport.CachedFiles.read_json(schema_file)) |> DataFrame.new()
  end

  # `{row index, code}` of every failing check.
  defp failures(checks) do
    for code <- DataFrame.names(checks), {false, row} <- Enum.with_index(Series.to_list(checks[code])), do: {row, code}
  end

  test "the generated files pass every field check" do
    for {role, rows} <- valid_rows(), do: assert(failures(checks(rows, role)) == [], "#{role}")
  end

  test "a missing value fails required, and the other rules of the field are not evaluated" do
    checks = valid_rows().statique |> put_first("nb_pdc", nil) |> checks(:statique)

    assert {checks["nb_pdc:required"][0], checks["nb_pdc:type"][0], checks["nb_pdc:minimum"][0]} == {false, nil, nil}
  end

  test "a value of the wrong type fails its type only, its constraints are not evaluated" do
    checks = valid_rows().statique |> put_first("station_latitude", "north") |> checks(:statique)

    assert failures(checks) == [{0, "station_latitude:type"}]
    assert {checks["station_latitude:minimum"][0], checks["station_latitude:maximum"][0]} == {nil, nil}
  end
end
