defmodule Transport.IRVE.V3.TarifsFixtureGeneratorTest do
  use ExUnit.Case, async: true
  alias Transport.IRVE.V3.{StaticFixtureGenerator, TarifsFixtureGenerator}
  doctest TarifsFixtureGenerator, import: true

  @schema Transport.CachedFiles.read_json("schema-irve-tarifs-v3.json")
  @now ~U[2026-10-01 00:00:00Z]

  defp static_rows, do: StaticFixtureGenerator.generate(seed: 7, stations: 50, networks: 3, now: @now)

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

  test "an announced tariff starts in the future, when its base tariff ends" do
    rows = generate()
    by_id = Map.new(rows, &{&1["tarif_id"], &1})

    for %{"tarif_id" => id, "start_date_time" => start} <- rows, String.ends_with?(id, "-v2") do
      assert DateTime.after?(start, @now)
      assert by_id[String.replace_suffix(id, "-v2", "")]["end_date_time"] == start
    end
  end

  test "energy prices rise with power bands, and are lower off-peak" do
    static = StaticFixtureGenerator.generate(seed: 7, stations: 300, networks: 20, now: @now)
    by_tarif = TarifsFixtureGenerator.generate(static, seed: 7, now: @now) |> Enum.group_by(& &1["tarif_id"])
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

  test "restrictions and price components conform to their JSON schemas" do
    restrictions = json_schema("schema-irve-tarifs-v3-restrictions.json")
    price_components = json_schema("schema-irve-tarifs-v3-price-components.json")

    for row <- generate() do
      assert ExJsonSchema.Validator.valid?(restrictions, row["restrictions"])
      assert ExJsonSchema.Validator.valid?(price_components, row["price_components"])
    end
  end
end
