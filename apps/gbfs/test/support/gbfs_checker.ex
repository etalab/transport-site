defmodule GBFS.Checker do
  @moduledoc """
  A way to check if a GBFS is valid
  """
  use ExUnit.CaseTemplate

  defp assert_keys_in_map(values, b) do
    values = MapSet.new(values)
    keys = b |> Map.keys() |> MapSet.new()
    assert values |> MapSet.subset?(keys), "#{inspect(values)} not in #{inspect(keys)}"
  end

  def check_entrypoint(body) do
    assert_keys_in_map(["version", "ttl", "last_updated", "data"], body)

    assert(Enum.count(body["data"]["fr"]["feeds"]) >= 3)
  end

  def check_system_information(body) do
    assert_keys_in_map(["version", "ttl", "last_updated", "data"], body)

    assert_keys_in_map(["language", "name", "system_id", "timezone"], body["data"])
  end

  def check_station_information(body) do
    assert_keys_in_map(["version", "ttl", "last_updated", "data"], body)
    assert body["ttl"] >= 0 && body["ttl"] <= 300

    stations = body["data"]["stations"]
    assert Enum.count(stations) > 0

    station = Enum.at(stations, 0)

    assert_keys_in_map(["capacity", "lat", "lon", "name", "station_id"], station)

    assert station["capacity"] > 0
  end

  def check_station_status(body) do
    assert_keys_in_map(["version", "ttl", "last_updated", "data"], body)
    assert body["ttl"] >= 0 && body["ttl"] <= 300

    stations = body["data"]["stations"]
    assert Enum.count(stations) > 0

    station = Enum.at(stations, 0)

    assert_keys_in_map(
      [
        "is_installed",
        "is_renting",
        "is_returning",
        "last_reported",
        "num_bikes_available",
        "num_docks_available",
        "station_id"
      ],
      station
    )

    assert station["num_docks_available"] >= 0 && station["num_docks_available"] < 1000
    assert station["num_bikes_available"] >= 0 && station["num_bikes_available"] < 1000
  end
end
