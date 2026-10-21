defmodule Transport.IRVE.V3.DynamicFixtureGenerator do
  @moduledoc """
  Seeded generator of IRVE dynamic v3 rows, matching rows from `Transport.IRVE.V3.StaticFixtureGenerator`.

  MVP, largely AI-generated, same spirit and constraints as the static generator. In addition:

  - one row per static point of charge, `id_pdc_itinerance` being a foreign key to the static file;
  - a connector state is filled only for the connector types declared on the static row, left empty otherwise.
  """

  alias Transport.IRVE.V3.StaticFixtureGenerator

  # Values are drawn uniformly from each list: repetitions act as weights.
  @etat_pdc List.duplicate("en_service", 16) ++ ["hors_service", "hors_service", "inconnu"]
  @occupation_pdc ["libre", "libre", "occupe", "inconnu"]
  # The connectors of a point follow its state.
  @etat_prise %{"en_service" => "fonctionnel", "hors_service" => "hors_service", "inconnu" => "inconnu"}

  @doc """
  Generates one row per static row: maps keyed by schema field name, `nil` for empty cells.

  Options: `:seed`, `:now` (upper bound for all timestamps).
  """
  def generate(static_rows, opts \\ []) do
    opts = Keyword.validate!(opts, seed: 1, now: ~U[2026-10-01 00:00:00Z])
    connector_fields = for "etat_" <> prise <- field_names(), do: {"etat_" <> prise, prise}

    # A dedicated process keeps the seeded `:rand` state away from the caller's.
    Task.async(fn ->
      :rand.seed(:exsss, opts[:seed])
      Enum.map(static_rows, &build_row(&1, connector_fields, opts[:now]))
    end)
    |> Task.await(:infinity)
  end

  def to_csv(rows), do: StaticFixtureGenerator.to_csv(rows, field_names())

  def field_names do
    Transport.CachedFiles.read_json("schema-irve-dynamique-v3.json")
    |> Map.fetch!("fields")
    |> Enum.map(&Map.fetch!(&1, "name"))
  end

  defp build_row(static_row, connector_fields, now) do
    etat_pdc = Enum.random(@etat_pdc)
    # Only points open to booking can be reserved.
    occupation = if static_row["reservation"], do: ["reserve" | @occupation_pdc], else: @occupation_pdc

    connectors =
      Map.new(connector_fields, fn {etat_field, prise_field} ->
        {etat_field, if(static_row[prise_field], do: @etat_prise[etat_pdc])}
      end)

    Map.merge(connectors, %{
      "id_pdc_itinerance" => static_row["id_pdc_itinerance"],
      "etat_pdc" => etat_pdc,
      "occupation_pdc" => Enum.random(occupation),
      # States are pushed on change: a timestamp is as old as the last change, within the day.
      "horodatage" => DateTime.add(now, -Enum.random(0..(24 * 3600)), :second)
    })
  end
end
