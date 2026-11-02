defmodule Transport.IRVE.V3.DynamicFixtureGeneratorTest do
  use ExUnit.Case, async: true
  alias Transport.IRVE.V3.{DynamicFixtureGenerator, StaticFixtureGenerator}

  @schema Transport.CachedFiles.read_json("schema-irve-dynamique-v3.json")
  @now ~U[2026-10-01 00:00:00Z]

  defp static_rows, do: StaticFixtureGenerator.generate(seed: 7, stations: 50, networks: 3, now: @now)

  defp generate(opts \\ []),
    do: DynamicFixtureGenerator.generate(static_rows(), Keyword.merge([seed: 7, now: @now], opts))

  test "the same seed gives the same file, another seed a different one" do
    csv = generate() |> DynamicFixtureGenerator.to_csv()

    assert csv == generate() |> DynamicFixtureGenerator.to_csv()
    refute csv == generate(seed: 8) |> DynamicFixtureGenerator.to_csv()
  end

  test "does not alter the caller's random state" do
    rows = static_rows()
    :rand.seed(:exsss, 123)
    expected = :rand.uniform(1_000_000)

    :rand.seed(:exsss, 123)
    DynamicFixtureGenerator.generate(rows)
    assert :rand.uniform(1_000_000) == expected
  end

  test "columns follow the schema, in order" do
    [header | _rows] = generate() |> DynamicFixtureGenerator.to_csv() |> String.split("\r\n")

    assert String.split(header, ",") == Enum.map(@schema["fields"], & &1["name"])
  end

  test "each static point gets one state, consistent with its connectors" do
    static_rows = static_rows()
    rows = DynamicFixtureGenerator.generate(static_rows, seed: 7, now: @now)
    prises = ~w(prise_type_2 prise_type_combo_ccs prise_type_chademo prise_type_ef prise_type_mcs)

    assert Enum.map(rows, & &1["id_pdc_itinerance"]) == Enum.map(static_rows, & &1["id_pdc_itinerance"])

    for {row, static_row} <- Enum.zip(rows, static_rows) do
      for prise <- prises, do: assert(is_nil(row["etat_" <> prise]) == not static_row[prise])
      if row["occupation_pdc"] == "reserve", do: assert(static_row["reservation"])
      assert DateTime.compare(row["horodatage"], @now) != :gt
    end
  end
end
