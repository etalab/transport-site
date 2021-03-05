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

  @spec convert_datetime_paris_zone(Calendar.datetime() | nil) :: Calendar.datetime() | binary()
  def convert_datetime_paris_zone(nil), do: ""

  def convert_datetime_paris_zone(datetime) do
    Timezone.convert(datetime, "Europe/Paris")
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
  end

  @spec admin?(map | nil) :: boolean
  def admin?(%{} = user) do
    user
    |> Map.get("organizations", [])
    |> Enum.any?(fn org -> org["slug"] == "equipe-transport-data-gouv-fr" end)
  end

  def admin?(nil), do: false
end
