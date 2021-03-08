defmodule Helpers do
  @moduledoc """
  Helper functions that are used accross the whole project
  """

  alias Timex.Format.DateTime.Formatter
  alias Timex.Timezone
  require Logger

  @doc """
  Gets the filename part of an url

  ## Examples

  iex> Helpers.filename_from_url("https://example.com/gtfs.zip")
  "gtfs.zip"

  iex> Helpers.filename_from_url("https://example.com/foo/bar/baz/bobette/")
  "bobette"
  """
  @spec filename_from_url(binary()) :: binary()
  def filename_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> String.trim_trailing("/")
    |> String.split("/")
    |> List.last()
  end

  @doc """
  Converts a Calendar.datetime to Paris datetime and then to a binary format ready for display.

  ## Examples

  iex> Helpers.convert_datetime_paris_zone(nil)
  ""

  iex> {:ok, dt, 0} = DateTime.from_iso8601("2020-03-08T00:00:00Z")
  {:ok, ~U[2020-03-08 00:00:00Z], 0}
  iex> Helpers.convert_datetime_paris_zone(dt)
  "2020-03-08T01:00:00+01:00"
  """
  @spec convert_datetime_paris_zone(Calendar.datetime() | nil) :: binary()
  def convert_datetime_paris_zone(nil), do: ""

  def convert_datetime_paris_zone(datetime) do
    with converted_date <- Timezone.convert(datetime, "Europe/Paris"),
         {:ok, formatted_date} <- Formatter.format(converted_date, "{RFC3339}") do
      formatted_date
    else
      {:error, error} ->
        Logger.error(error)
        ""
    end
  end

  @doc """
  Converts a binary date to a Paris binary date. Ultimately, this function should disappear because all datetimes in our databases will be datetimes, not strings

  ## Examples

  iex> Helpers.format_datetime("2020-03-08T00:00:00+00:00")
  "2020-03-08T01:00:00+01:00"
  """
  @spec format_datetime(binary()) :: binary()
  def format_datetime(nil), do: ""

  def format_datetime(date) do
    with {:ok, parsed_date} <- Timex.parse(date, "{ISO:Extended}"),
         formatted_date <- convert_datetime_paris_zone(parsed_date) do
      formatted_date
    else
      {:error, error} ->
        Logger.error(error)
        ""
    end
  end

  @spec last_updated([DB.Resource.t()]) :: binary()
  def last_updated(resources) do
    resources
    |> Enum.map(fn r -> r.last_update end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dates -> Enum.max(dates)
    end
    |> convert_datetime_paris_zone
  end

  @spec admin?(map | nil) :: boolean
  def admin?(%{} = user) do
    user
    |> Map.get("organizations", [])
    |> Enum.any?(fn org -> org["slug"] == "equipe-transport-data-gouv-fr" end)
  end

  def admin?(nil), do: false
end
