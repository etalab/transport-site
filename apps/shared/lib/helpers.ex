defmodule Helpers do
  @moduledoc """
  Helper functions that are used accross the whole project
  """
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
  def filename_from_url(url) when is_binary(url) do
    url
    |> URI.parse()
    |> Map.get(:path)
    |> String.trim_trailing("/")
    |> String.split("/")
    |> List.last()
  end

  def filename_from_url(_), do: nil

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

  @doc """
  Formats numbers, allowing for nil to be passed and formatted specifically

  ## Examples

  iex> Helpers.format_number_maybe_nil(12_345, nil_result: "N/C")
  "12 345"

  iex> Helpers.format_number_maybe_nil(nil, nil_result: "N/C")
  "N/C"
  """
  def format_number_maybe_nil(nil, options), do: options |> Keyword.fetch!(:nil_result)
  def format_number_maybe_nil(n, options), do: format_number(n, options |> Keyword.delete(:nil_result))

  @spec last_updated([DB.Resource.t()]) :: binary()
  def last_updated(resources) do
    resources
    |> Enum.map(& &1.last_update)
    |> case do
      [] -> nil
      dates -> dates |> Enum.max(DateTime) |> DateTime.to_iso8601()
    end
  end
end
