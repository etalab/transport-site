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
  - a point may also list `<base id>-v2`, a tariff starting on the first day of next month, when its base
    tariff ends, with no end date (our convention, not a schema rule).
  """

  alias Transport.IRVE.V3.StaticFixtureGenerator

  # TTC prices: €/kWh for ENERGY, €/h for TIME and PARKING_TIME, € for FLAT.
  # Values are drawn uniformly from each list: repetitions act as weights.
  @ac [0.30, 0.35, 0.38, 0.39, 0.40, 0.44, 0.47, 0.49]
  @dc [0.45, 0.49, 0.53, 0.55, 0.59, 0.61, 0.65]
  @off_peak [0.22, 0.23, 0.24, 0.27, 0.31]
  @week ~w(MONDAY TUESDAY WEDNESDAY THURSDAY FRIDAY SATURDAY SUNDAY)

  # Overstay fee: while the session lasts between 1 h and 5 h 10, 24 €/h on charging time (TIME)
  # and on idle time (PARKING_TIME).
  @overstay {%{"min_duration" => 3600, "max_duration" => 18_600}, [{"TIME", [24.0], 60}, {"PARKING_TIME", [24.0], 60}]}

  # Elements as `{restrictions, [{component type, prices, step_size}]}`. As in OCPI, each component
  # type is taken from the first element carrying it whose restrictions match.
  @shapes %{
    false => [
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
      ],
      [{%{"max_power" => 49.0}, [{"ENERGY", @ac, 1}]}, {%{"min_power" => 50.0}, [{"ENERGY", @dc, 1}]}]
    ],
    true => [
      [{%{}, [{"ENERGY", @dc, 1}]}],
      [{%{}, [{"ENERGY", @dc, 1}]}],
      [{%{}, [{"ENERGY", @dc, 1000}]}, @overstay],
      # Time of day, split at midnight, with an unrestricted fallback.
      [
        {%{"start_time" => "00:00", "end_time" => "09:00", "day_of_week" => @week}, [{"ENERGY", @off_peak, 1}]},
        {%{"start_time" => "09:00", "end_time" => "20:00", "day_of_week" => @week}, [{"ENERGY", @dc, 1}]},
        {%{"start_time" => "20:00", "end_time" => "00:00", "day_of_week" => @week}, [{"ENERGY", @off_peak, 1}]},
        {%{}, [{"ENERGY", @dc, 1}]}
      ],
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
    # A tariff is shaped after the current (AC/DC) of the first point referencing it.
    tarifs =
      for(row <- static_rows, id <- row["tarif_ids"] || [], do: {id, row["courant_dc"]}) |> Enum.uniq_by(&elem(&1, 0))

    ids = MapSet.new(tarifs, &elem(&1, 0))
    switch = DateTime.new!(opts[:now] |> DateTime.to_date() |> Date.end_of_month() |> Date.add(1), ~T[00:00:00])

    # A dedicated process keeps the seeded `:rand` state away from the caller's.
    Task.async(fn ->
      :rand.seed(:exsss, opts[:seed])
      Enum.flat_map(tarifs, fn {id, courant_dc} -> build_tarif(id, courant_dc, ids, switch, opts[:now]) end)
    end)
    |> Task.await(:infinity)
  end

  def to_csv(rows), do: StaticFixtureGenerator.to_csv(rows, field_names())

  def field_names do
    Transport.CachedFiles.read_json("schema-irve-tarifs-v3.json")
    |> Map.fetch!("fields")
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  defp build_tarif(id, courant_dc, ids, switch, now) do
    started = DateTime.new!(Date.add(DateTime.to_date(now), -Enum.random(30..730)), ~T[00:00:00])

    tarif = %{
      "tarif_id" => id,
      "devise" => "EUR",
      "horodatage_maj_tarif" => DateTime.add(now, -Enum.random(0..(400 * 24 * 3600)), :second),
      "start_date_time" => if(String.ends_with?(id, "-v2"), do: switch, else: Enum.random([nil, started])),
      "end_date_time" => if((id <> "-v2") in ids, do: switch),
      "type" => "AD_HOC_PAYMENT",
      "tax_included" => "YES",
      "min_price" => Enum.random([nil, nil, nil, 0.5, 1.0]),
      "max_price" => Enum.random([nil, nil, nil, nil, 60.0])
    }

    @shapes[courant_dc]
    |> Enum.random()
    |> Enum.with_index(fn {restrictions, components}, index ->
      prices =
        for {type, prices, step} <- components,
            do: %{"type" => type, "price" => Enum.random(prices), "step_size" => step}

      Map.merge(tarif, %{"element_index" => index, "restrictions" => restrictions, "price_components" => prices})
    end)
  end
end
