defmodule Shared.DateTimeDisplay do
  @moduledoc """
  A module to have a coherent display of dates and times accross the website.
  The goal is to show date times for Europe/Paris timezone to our users.
  """
  @doc """
  Formats a date to display depending on the locale

  iex> format_date(~D[2022-03-01], "fr")
  "01/03/2022"
  iex> format_date(~D[2022-03-01], "en")
  "2022-03-01"
  iex> format_date("2022-03-01", "fr")
  "01/03/2022"
  iex> format_date("2022-03-01", "sauce tomate")
  "01/03/2022"
  iex> format_date("2022-03-01", "en")
  "2022-03-01"
  iex> format_date(~U[2022-11-01 00:00:00Z], "en")
  "2022-11-01"
  """
  @spec format_date(binary | Date.t() | DateTime.t(), binary() | nil) :: binary
  def format_date(%DateTime{} = datetime, locale), do: format_date(DateTime.to_date(datetime), locale)
  def format_date(%Date{} = date, "fr"), do: Calendar.strftime(date, "%d/%m/%Y")
  def format_date(%Date{} = date, "en"), do: Calendar.strftime(date, "%Y-%m-%d")
  def format_date(%Date{} = date, _), do: format_date(date, "fr")

  def format_date(date, locale) when is_binary(date) do
    date |> Date.from_iso8601!() |> format_date(locale)
  end

  def format_date(nil, _), do: ""

  def format_date(date, locale, iso_extended: true) do
    date |> Timex.parse!("{ISO:Extended}") |> format_date(locale)
  end

  @doc """
  Display a date from a DateTime

  iex> format_datetime_to_date(~U[2022-03-01T15:00:00Z], "fr")
  "01/03/2022"
  iex> format_datetime_to_date(~U[2022-03-01T15:00:00Z], "en")
  "2022-03-01"
  """
  def format_datetime_to_date(%DateTime{} = dt, locale) do
    dt |> DateTime.to_date() |> format_date(locale)
  end

  def format_datetime_to_date(nil, _), do: ""

  @doc """
  Formats a date time for display.
  Input can be in any timezone, outputs is in Europe/Paris timezone.

  iex> format_datetime_to_paris(~U[2022-03-01 15:30:00+00:00], "fr")
  "01/03/2022 à 16h30 Europe/Paris"
  iex> format_datetime_to_paris(~U[2022-03-01 15:30:00+00:00], "en")
  "2022-03-01 at 16:30 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:00Z", "fr")
  "01/03/2022 à 16h30 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:00Z", "sauce tomate")
  "01/03/2022 à 16h30 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:00+01:00", "fr")
  "01/03/2022 à 15h30 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:00+01:00", "fr")
  "01/03/2022 à 15h30 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:09+01:00", "fr", with_seconds: true)
  "01/03/2022 à 15:30:09 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:00+00:00", "en")
  "2022-03-01 at 16:30 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:09+00:00", "en", with_seconds: true)
  "2022-03-01 at 16:30:09 Europe/Paris"
  # right before daylight hour change
  iex> format_datetime_to_paris("2022-03-27T00:59+00:00", "fr")
  "27/03/2022 à 01h59 Europe/Paris"
  # right after daylight hour change
  iex> format_datetime_to_paris("2022-03-27T01:00:00+00:00", "fr")
  "27/03/2022 à 03h00 Europe/Paris"
  """
  def format_datetime_to_paris(dt, locale), do: format_datetime_to_paris(dt, locale, [])

  def format_datetime_to_paris(%DateTime{} = dt, locale, options) do
    format = get_localized_format(locale, options)
    format = if !Keyword.get(options, :no_timezone), do: format <> " Europe/Paris", else: format
    dt |> convert_to_paris_time() |> Calendar.strftime(format)
  end

  def format_datetime_to_paris(%NaiveDateTime{} = ndt, locale, options) do
    ndt
    |> convert_to_paris_time()
    |> format_datetime_to_paris(locale, options)
  end

  def format_datetime_to_paris(datetime, locale, options) when is_binary(datetime) do
    datetime
    |> Timex.parse!("{ISO:Extended}")
    |> format_datetime_to_paris(locale, options)
  end

  def format_datetime_to_paris(nil, _, _), do: ""

  @spec convert_to_paris_time(DateTime.t() | NaiveDateTime.t()) :: DateTime.t()
  defp convert_to_paris_time(%DateTime{} = dt) do
    case Timex.Timezone.convert(dt, "Europe/Paris") do
      %Timex.AmbiguousDateTime{after: dt} -> dt
      %DateTime{} = dt -> dt
    end
  end

  defp convert_to_paris_time(%NaiveDateTime{} = ndt) do
    case Timex.Timezone.convert(ndt, "Europe/Paris") do
      %Timex.AmbiguousDateTime{after: dt} -> dt
      %DateTime{} = dt -> dt
    end
  end

  defp get_localized_format("en", options) do
    if Keyword.get(options, :with_seconds) do
      "%Y-%m-%d at %H:%M:%S"
    else
      "%Y-%m-%d at %H:%M"
    end
  end

  defp get_localized_format(_locale, options) do
    if Keyword.get(options, :with_seconds) do
      "%d/%m/%Y à %H:%M:%S"
    else
      "%d/%m/%Y à %Hh%M"
    end
  end
end
