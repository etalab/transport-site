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
  Formats numbers.

  See options: https://hexdocs.pm/ex_cldr_numbers/readme.html#primary-public-api

  ## Examples

  iex> Helpers.format_number(12_345)
  "12 345"

  iex> Helpers.format_number(12_345.42)
  "12 345,42"

  iex> Helpers.format_number(12_345, locale: "en")
  "12,345"
  """
  def format_number(n, options \\ []) when is_number(n) do
    {:ok, res} = Transport.Cldr.Number.to_string(n, options)
    res
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
    |> Shared.DateTimeDisplay.format_naive_datetime_to_paris_tz()
  end

  @spec admin?(map | nil) :: boolean
  def admin?(%{} = user) do
    user
    |> Map.get("organizations", [])
    |> Enum.any?(fn org -> org["slug"] == "equipe-transport-data-gouv-fr" end)
  end

  def admin?(nil), do: false
end
