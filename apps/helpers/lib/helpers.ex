defmodule  Helpers do
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
  def filename_from_url(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> String.trim_trailing("/")
    |> String.split("/")
    |> List.last()
  end

  def format_datetime(nil), do: ""
  def format_datetime(date) do
    with {:ok, parsed_date} <- Timex.parse(date, "{ISO:Extended}"),
          converted_date <- Timezone.convert(parsed_date, "Europe/Paris"),
          {:ok, formatted_date} <- Formatter.format(converted_date, "{RFC3339}") do
      formatted_date
    else
      {:error, error} ->
        Logger.error(error)
        ""
    end
  end

  def last_updated(resources) do
    resources
    |> Enum.map(fn r -> r.last_update end)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      dates -> Enum.max(dates)
    end
    |> format_datetime()
  end
end
