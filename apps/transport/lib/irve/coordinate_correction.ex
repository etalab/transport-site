defmodule Transport.IRVE.CoordinateCorrection do
  @moduledoc """
  Detects and corrects lon/lat coordinate inversions in IRVE data.

  Some producers submit `coordonneesXY` as `[latitude, longitude]` instead of the
  schema-required `[longitude, latitude]`. Detection is based on a bounding box for
  metropolitan France + Corsica (lon ∈ [-5.5, 9.7], lat ∈ [41.0, 51.5]); see `inverted?/2`.
  """

  @metro_lon_min -5.5
  @metro_lon_max 9.7
  @metro_lat_min 41.0
  @metro_lat_max 51.5

  require Explorer.DataFrame, as: DF
  alias Explorer.Series

  @doc """
  Corrects inverted coordinates in a DataFrame with `longitude` and `latitude` float
  columns. Adds `consolidated_is_lon_lat_correct` (`false` = row was swapped).

      iex> df = Explorer.DataFrame.new(longitude: [2.35, 48.85, 55.4], latitude: [48.85, 2.35, -21.1])
      iex> r = Transport.IRVE.CoordinateCorrection.detect_and_correct(df)
      iex> Explorer.Series.to_list(r["longitude"])
      [2.35, 2.35, 55.4]
      iex> Explorer.Series.to_list(r["latitude"])
      [48.85, 48.85, -21.1]
      iex> Explorer.Series.to_list(r["consolidated_is_lon_lat_correct"])
      [true, false, true]

  """
  def detect_and_correct(%DF{} = df) do
    DF.mutate_with(df, fn df ->
      lon = df["longitude"]
      lat = df["latitude"]
      inverted = inverted?(lon, lat)

      %{
        longitude: Series.select(inverted, lat, lon),
        latitude: Series.select(inverted, lon, lat),
        consolidated_is_lon_lat_correct: Series.not(inverted)
      }
    end)
  end

  @doc """
  Returns a boolean Series: `true` where `lon_series` ∈ [#{@metro_lat_min}, #{@metro_lat_max}]
  AND `lat_series` ∈ [#{@metro_lon_min}, #{@metro_lon_max}].

  Test cases:

  1. Metro France, correct — lon 2.35 (Paris), not in lat range → `false`
  2. Metro France, inverted — lon 48.85 is in [41, 51.5] and lat 2.35 is in [-5.5, 9.7] → `true`
  3. Mayotte, correct — lon 45.1 falls in the lat range [41, 51.5], but lat −12.8 is
     below −5.5, so both conditions are not met → `false`
  4. Corsica, inverted — edge case: lat 9.56 is just above the 9.5 ceiling one might
     naively use; the 9.7 upper bound is required to catch it → `true`

      iex> lon = Explorer.Series.from_list([2.35, 48.85, 45.1, 42.4])
      iex> lat = Explorer.Series.from_list([48.85, 2.35, -12.8, 9.56])
      iex> Explorer.Series.to_list(Transport.IRVE.CoordinateCorrection.inverted?(lon, lat))
      [false, true, false, true]

  """
  def inverted?(lon_series, lat_series) do
    lon_in_lat_range =
      Series.and(
        Series.greater_equal(lon_series, @metro_lat_min),
        Series.less_equal(lon_series, @metro_lat_max)
      )

    lat_in_lon_range =
      Series.and(
        Series.greater_equal(lat_series, @metro_lon_min),
        Series.less_equal(lat_series, @metro_lon_max)
      )

    Series.and(lon_in_lat_range, lat_in_lon_range)
  end
end
