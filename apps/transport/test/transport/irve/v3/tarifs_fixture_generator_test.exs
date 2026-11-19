defmodule Transport.IRVE.V3.TarifsFixtureGeneratorTest do
  use ExUnit.Case, async: true
  alias Transport.IRVE.V3.{StaticFixtureGenerator, TarifsFixtureGenerator}
  doctest TarifsFixtureGenerator, import: true

  @schema Transport.CachedFiles.read_json("schema-irve-tarifs-v3.json")
  @now ~U[2026-10-01 00:00:00Z]

  # Enough networks for every tariff scope and shape to show up.
  defp static_rows, do: StaticFixtureGenerator.generate(seed: 7, stations: 300, networks: 20, now: @now)

  defp generate(opts \\ []),
    do: TarifsFixtureGenerator.generate(static_rows(), Keyword.merge([seed: 7, now: @now], opts))

  defp json_schema(file), do: file |> Transport.CachedFiles.read_json() |> ExJsonSchema.Schema.resolve()

  test "the same seed gives the same file, another seed a different one" do
    csv = generate() |> TarifsFixtureGenerator.to_csv()

    assert csv == generate() |> TarifsFixtureGenerator.to_csv()
    refute csv == generate(seed: 8) |> TarifsFixtureGenerator.to_csv()
  end

  test "does not alter the caller's random state" do
    rows = static_rows()
    :rand.seed(:exsss, 123)
    expected = :rand.uniform(1_000_000)

    :rand.seed(:exsss, 123)
    TarifsFixtureGenerator.generate(rows)
    assert :rand.uniform(1_000_000) == expected
  end

  test "columns follow the schema, in order" do
    [header | _rows] = generate() |> TarifsFixtureGenerator.to_csv() |> String.split("\r\n")

    assert String.split(header, ",") == Enum.map(@schema["fields"], & &1["name"])
  end

  test "describes exactly the tariffs referenced by the static points" do
    referenced = static_rows() |> Enum.flat_map(&(&1["tarif_ids"] || [])) |> MapSet.new()

    assert generate() |> MapSet.new(& &1["tarif_id"]) == referenced
  end

  test "elements are indexed from 0 and share their tariff fields" do
    tarif_fields = for %{"name" => name, "x-entity" => "tarif"} <- @schema["fields"], do: name

    for {_id, [first | _] = rows} <- generate() |> Enum.group_by(& &1["tarif_id"]) do
      assert Enum.map(rows, & &1["element_index"]) == Enum.to_list(0..(length(rows) - 1))
      assert Enum.all?(rows, &(Map.take(&1, tarif_fields) == Map.take(first, tarif_fields)))
    end
  end

  test "a successor either started after its base tariff, left open, or is announced for when it ends" do
    by_id = generate() |> Map.new(&{&1["tarif_id"], &1})

    successors =
      for {id, successor} <- by_id,
          String.ends_with?(id, "-v2"),
          do: {by_id[String.replace_suffix(id, "-v2", "")], successor}

    {announced, started} =
      Enum.split_with(successors, fn {_base, v2} -> DateTime.after?(v2["start_date_time"], @now) end)

    assert announced != [] and started != []

    for {base, v2} <- announced, do: assert(base["end_date_time"] == v2["start_date_time"])

    for {base, v2} <- started do
      assert is_nil(base["end_date_time"])
      assert v2["start_date_time"] == v2["horodatage_maj_tarif"]
      assert DateTime.after?(v2["start_date_time"], base["horodatage_maj_tarif"])
    end
  end

  test "energy prices rise with power bands, and are lower off-peak" do
    by_tarif = generate() |> Enum.group_by(& &1["tarif_id"])
    energy = fn row -> for %{"type" => "ENERGY", "price" => price} <- row["price_components"], do: price end

    banded = for {_id, rows} <- by_tarif, Enum.any?(rows, &(&1["restrictions"]["min_power"] != nil)), do: rows
    timed = for {_id, rows} <- by_tarif, Enum.any?(rows, &(&1["restrictions"]["start_time"] != nil)), do: rows
    assert banded != [] and timed != []

    for rows <- banded, do: assert(Enum.flat_map(rows, energy) == Enum.sort(Enum.flat_map(rows, energy)))

    for rows <- timed do
      {[off_peak, peak, off_peak], _fallback} = rows |> Enum.flat_map(energy) |> Enum.split(3)
      assert off_peak < peak
    end
  end

  test "a network sets a minimum price on all its tariffs or on none" do
    rows = generate()
    flags = rows |> Enum.group_by(&String.slice(&1["tarif_id"], 2, 3), &(&1["min_price"] != nil)) |> Map.values()

    assert Enum.all?(flags, &match?([_], Enum.uniq(&1)))
    assert flags |> Enum.map(&hd/1) |> Enum.uniq() |> Enum.sort() == [false, true]
    assert Enum.all?(rows, &is_nil(&1["max_price"]))
  end

  test "restrictions and price components conform to their JSON schemas" do
    restrictions = json_schema("schema-irve-tarifs-v3-restrictions.json")
    price_components = json_schema("schema-irve-tarifs-v3-price-components.json")

    for row <- generate() do
      assert ExJsonSchema.Validator.valid?(restrictions, row["restrictions"])
      assert ExJsonSchema.Validator.valid?(price_components, row["price_components"])
    end
  end
end
