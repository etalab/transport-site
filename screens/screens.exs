defmodule Transport.Data.Screens do
  use ExUnit.Case

  import Ecto.Query, only: [from: 2]

  test "converts every GTFS to GeoJSON" do
    %{rows: [[originals_count]]} = Ecto.Adapters.SQL.query!(DB.Repo, """
    select count(*) from resource_history where payload->>'format' = 'GTFS'
    """)

    %{rows: [[conversions_count]]} = Ecto.Adapters.SQL.query!(DB.Repo, """
    select count(*) from data_conversion where convert_from = 'GTFS' and convert_to = 'GeoJSON'
    """)

    assert conversions_count == originals_count
  end

  test "converts every GTFS to NeTEX" do
    %{rows: [[originals_count]]} = Ecto.Adapters.SQL.query!(DB.Repo, """
    select count(*) from resource_history where payload->>'format' = 'GTFS'
    """)

    %{rows: [[conversions_count]]} = Ecto.Adapters.SQL.query!(DB.Repo, """
    select count(*) from data_conversion where convert_from = 'GTFS' and convert_to = 'NeTEx'
    """)

    assert conversions_count == originals_count
  end
end

ExUnit.start
