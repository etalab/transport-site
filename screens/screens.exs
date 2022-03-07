defmodule EasyInspect do
  def show(x) do
    IO.inspect(x, IEx.inspect_opts)
  end
end

defmodule Transport.Data.Screens do
  use ExUnit.Case
  import EasyInspect


  import Ecto.Query

  test "resources without resource history" do
    # TODO: dump a report somewhere on disk
    # TODO: let LiveBook show the result in exploratory fashion
    # TODO: move the code to the right place so that we can call it from anywhere
    result = Transport.Screens.resources_with_duplicate_datagouv_id()
    assert result == [], result |> inspect
  end

  @tag :focus
  test "resources (or datagouv_id, actually, at the moment) without at least one resource history" do
    # TODO: dump / report
    non_nil_datagouv_ids = DB.Resource
    |> where([r], not is_nil(r.datagouv_id))
    |> select([r], map(r, [:datagouv_id]))
    |> DB.Repo.all()
    |> Enum.map(fn(x) -> x[:datagouv_id] end)
    |> show

  end

  # TODO: replace what's below with Elixir + Ecto code (for clarity / composability / maintenance)

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

ExUnit.configure(exclude: :test, include: :focus)
ExUnit.start()
