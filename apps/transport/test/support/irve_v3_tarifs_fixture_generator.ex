defmodule Transport.IRVE.V3.TarifsFixtureGenerator do
  @moduledoc """
  Seeded generator of IRVE tarifs v3 rows: the tariffs targeted by the `tarif_ids` foreign keys
  of `Transport.IRVE.V3.StaticFixtureGenerator` rows.

  Data model (3 files, keys, diagram): https://github.com/etalab/schema-irve/blob/v3.0.0-alpha.1/docs/note-conception-irve-v3.md#2-modèle-de-données

  MVP, largely AI-generated, same spirit and constraints as the static generator. In addition:

  - every `tarif_id` referenced by the static rows (`-v2` ones included) is described, and no other;
    one row per tariff element (`element_index` from 0), tariff-level fields repeated on every row;
  - shapes and prices follow real OCPI ad hoc tariffs sampled from QualiCharge, translated to v3
    (TTC prices, `HH:MM` times, no `CONGESTION_TIME`);
  - a tariff's shape depends on the currents of the points referencing it (AC, DC or both); power bands
    only appear in tariffs covering both, where they tell AC and DC points apart;
  - some networks set a `min_price` on all their tariffs, mostly 0.50 €, as BMP does; `max_price` is never
    set, as in real data;
  - the points of a tariff may also list `<base id>-v2`, a tariff starting on the first day of next month,
    when its base tariff ends, with no end date (our convention, not a schema rule).
  """

  alias Transport.IRVE.V3.StaticFixtureGenerator

  # TTC prices: €/kWh for ENERGY, €/h for TIME and PARKING_TIME, € for FLAT.
  # Lists sorted in ascending order: a tariff takes all its prices at one level (see `price_at/2`),
  # so that they rise with power and peak hours, as in real tariffs. Repetitions act as weights.
  @ac [0.30, 0.35, 0.38, 0.39, 0.40, 0.44, 0.47, 0.49]
  @dc [0.45, 0.49, 0.53, 0.55, 0.59, 0.61, 0.65]
  @off_peak [0.22, 0.23, 0.24, 0.27, 0.31]
  @week ~w(MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY SUNDAY)

  # Overstay fee: while the session lasts between 1 h and 5 h 10, 24 €/h on charging time (TIME)
  # and on idle time (PARKING_TIME).
  @overstay {%{"min_duration" => 3600, "max_duration" => 18_600}, [{"TIME", [24.0], 60}, {"PARKING_TIME", [24.0], 60}]}

  # Elements as `{restrictions, [{component type, prices, step_size}]}`. As in OCPI, each component
  # type is taken from the first element carrying it whose restrictions match.
  # Keyed by the currents of the points referencing the tariff.
  @shapes %{
    ac: [
      [{%{}, [{"ENERGY", @ac, 1}]}],
      [{%{}, [{"ENERGY", @ac, 1}]}],
      # Billed per started kWh.
      [{%{}, [{"ENERGY", @ac, 1000}]}],
      [{%{}, [{"FLAT", [1.0], 1}, {"ENERGY", @ac, 1}]}],
      [{%{}, [{"ENERGY", @ac, 1}]}, @overstay],
      # Idle fee once charging has started, free components stated explicitly.
      [
        {%{"min_kwh" => 0.1}, [{"PARKING_TIME", [7.2, 12.0, 18.0], 60}]},
        {%{}, [{"TIME", [0.0], 60}, {"ENERGY", @ac, 100}, {"PARKING_TIME", [0.0], 60}]}
      ]
    ],
    dc: [
      [{%{}, [{"ENERGY", @dc, 1}]}],
      [{%{}, [{"ENERGY", @dc, 1}]}],
      [{%{}, [{"ENERGY", @dc, 1000}]}, @overstay],
      # Time of day, split at midnight, with an unrestricted fallback.
      [
        {%{"start_time" => "00:00", "end_time" => "09:00", "day_of_week" => @week}, [{"ENERGY", @off_peak, 1}]},
        {%{"start_time" => "09:00", "end_time" => "20:00", "day_of_week" => @week}, [{"ENERGY", @dc, 1}]},
        {%{"start_time" => "20:00", "end_time" => "00:00", "day_of_week" => @week}, [{"ENERGY", @off_peak, 1}]},
        {%{}, [{"ENERGY", @dc, 1}]}
      ]
    ],
    # Power bands are what tells AC and DC points apart.
    ac_dc: [
      [{%{}, [{"ENERGY", @dc, 1}]}],
      [{%{"max_power" => 49.0}, [{"ENERGY", @ac, 1}]}, {%{"min_power" => 50.0}, [{"ENERGY", @dc, 1}]}],
      [
        {%{"max_power" => 44.0}, [{"ENERGY", @ac, 1}]},
        {%{"min_power" => 45.0, "max_power" => 149.0}, [{"ENERGY", @dc, 1}]},
        {%{"min_power" => 150.0}, [{"ENERGY", [0.59, 0.65, 0.69], 1}]}
      ]
    ]
  }

  @doc """
  Generates the elements of every tariff referenced by the static rows: maps keyed by schema field name,
  `nil` for empty cells.

  Options: `:seed`, `:now` (reference for all dates).
  """
  def generate(static_rows, opts \\ []) do
    opts = Keyword.validate!(opts, seed: 1, now: ~U[2026-10-01 00:00:00Z])

    tarifs =
      for(row <- static_rows, id <- row["tarif_ids"] || [], do: {id, row["courant_dc"]})
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.map(fn {id, courants_dc} -> {id, currents(courants_dc |> Enum.uniq() |> Enum.sort())} end)
      |> Enum.sort()

    ids = MapSet.new(tarifs, &elem(&1, 0))
    switch = DateTime.new!(opts[:now] |> DateTime.to_date() |> Date.end_of_month() |> Date.add(1), ~T[00:00:00])

    # A dedicated process keeps the seeded `:rand` state away from the caller's.
    Task.async(fn ->
      :rand.seed(:exsss, opts[:seed])
      Enum.flat_map(tarifs, fn {id, currents} -> build_tarif(id, currents, ids, switch, opts[:now]) end)
    end)
    |> Task.await(:infinity)
  end

  def to_csv(rows), do: StaticFixtureGenerator.to_csv(rows, field_names())

  def field_names do
    Transport.CachedFiles.read_json("schema-irve-tarifs-v3.json")
    |> Map.fetch!("fields")
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  @doc """
  Picks the price at `level`, from 0.0 (cheapest) to 1.0 (most expensive), in a list sorted in ascending order.
  The same level taken in a cheaper list (here AC, then DC) gives a lower price:

      iex> price_at([0.30, 0.40, 0.50], 0.6)
      0.40
      iex> price_at([0.45, 0.55, 0.65], 0.6)
      0.55
  """
  def price_at(prices, level), do: Enum.at(prices, round(level * (length(prices) - 1)))

  defp currents([false]), do: :ac
  defp currents([true]), do: :dc
  defp currents([false, true]), do: :ac_dc

  defp build_tarif(id, currents, ids, switch, now) do
    started = DateTime.new!(Date.add(DateTime.to_date(now), -Enum.random(30..730)), ~T[00:00:00])

    tarif = %{
      "tarif_id" => id,
      "devise" => "EUR",
      "horodatage_maj_tarif" => DateTime.add(now, -Enum.random(0..(400 * 24 * 3600)), :second),
      "start_date_time" => if(String.ends_with?(id, "-v2"), do: switch, else: Enum.random([nil, started])),
      "end_date_time" => if((id <> "-v2") in ids, do: switch),
      "type" => "AD_HOC_PAYMENT",
      "tax_included" => "YES",
      # Decided per network (trigram after "FR"), so that all its tariffs agree.
      "min_price" => if(:erlang.phash2(String.slice(id, 2, 3), 3) == 0, do: Enum.random([0.5, 0.5, 0.5, 0.5, 1.0])),
      "max_price" => nil
    }

    level = :rand.uniform()

    @shapes[currents]
    |> Enum.random()
    |> Enum.with_index(fn {restrictions, components}, index ->
      prices =
        for {type, prices, step} <- components,
            do: %{"type" => type, "price" => price_at(prices, level), "step_size" => step}

      Map.merge(tarif, %{"element_index" => index, "restrictions" => restrictions, "price_components" => prices})
    end)
  end
end
