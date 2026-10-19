defmodule Transport.IRVE.V3.StaticFixtureGeneratorTest do
  use ExUnit.Case, async: true
  alias Transport.IRVE.V3.StaticFixtureGenerator

  @schema Transport.CachedFiles.read_json("irve-v3/schema-statique.json")

  defp generate(opts \\ []),
    do: StaticFixtureGenerator.generate(Keyword.merge([seed: 7, stations: 50, networks: 3], opts))

  defp fields_of_entity(entity) do
    for %{"name" => name, "x-entity" => ^entity} <- @schema["fields"], do: name
  end

  test "the same seed gives the same file, another seed a different one" do
    csv = generate() |> StaticFixtureGenerator.to_csv()

    assert csv == generate() |> StaticFixtureGenerator.to_csv()
    refute csv == generate(seed: 8) |> StaticFixtureGenerator.to_csv()
  end

  test "does not alter the caller's random state" do
    :rand.seed(:exsss, 123)
    expected = :rand.uniform(1_000_000)

    :rand.seed(:exsss, 123)
    generate()
    assert :rand.uniform(1_000_000) == expected
  end

  test "columns follow the schema, in order" do
    [header | _rows] = generate(stations: 1) |> StaticFixtureGenerator.to_csv() |> String.split("\r\n")

    assert String.split(header, ",") == Enum.map(@schema["fields"], & &1["name"])
  end

  test "station-level fields are identical across the points of a station" do
    station_fields = fields_of_entity("station")

    for {_id, [first | _] = rows} <- generate() |> Enum.group_by(& &1["id_station_itinerance"]) do
      assert length(rows) == first["nb_pdc"]
      assert first["puissance_maximale_station_kw"] <= rows |> Enum.map(& &1["puissance_nominale_kw"]) |> Enum.sum()
      assert Enum.all?(rows, &(Map.take(&1, station_fields) == Map.take(first, station_fields)))
    end
  end

  test "points are consistent with their connectors and their station" do
    rows = generate()
    prises = ~w(prise_type_ef prise_type_2 prise_type_combo_ccs prise_type_chademo prise_type_mcs)

    assert rows |> Enum.map(& &1["id_pdc_itinerance"]) |> Enum.uniq() |> length() == length(rows)

    for row <- rows do
      assert row["nb_connecteurs"] >= Enum.count(prises, &row[&1]) + length(row["prise_type_autre"])
      assert row["courant_ac"] or row["courant_dc"]
      assert row["puissance_nominale_kw"] <= row["puissance_maximale_station_kw"]
      if row["gratuit"], do: assert(is_nil(row["tarif_ids"]) and is_nil(row["paiement_cb"]))

      [_, station_trigram] = Regex.run(~r/^FR(...)P/, row["id_station_itinerance"])
      assert String.starts_with?(row["id_pdc_itinerance"], "FR#{station_trigram}E")
    end
  end
end
