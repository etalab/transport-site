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
  iex> format_date("2022-02-21T14:28:09.366000+00:00", "fr", iso_extended: true)
  "21/02/2022"
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
    date |> TimeWrapper.parse!("{ISO:Extended}") |> format_date(locale)
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
  iex> format_datetime_to_paris(~N[2022-03-01 15:30:00.0000], "en")
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
  iex> format_datetime_to_paris("2022-03-27T01:00:00+00:00", "fr", no_timezone: true)
  "27/03/2022 à 03h00"
  """
  def format_datetime_to_paris(dt, locale), do: format_datetime_to_paris(dt, locale, [])

  def format_datetime_to_paris(%DateTime{} = dt, locale, options) do
    format = get_localized_datetime_format(locale, options)
    format = if Keyword.get(options, :no_timezone), do: format, else: format <> " Europe/Paris"
    dt |> convert_to_paris_time() |> Calendar.strftime(format)
  end

  def format_datetime_to_paris(%NaiveDateTime{} = ndt, locale, options) do
    ndt
    |> convert_to_paris_time()
    |> format_datetime_to_paris(locale, options)
  end

  def format_datetime_to_paris(datetime, locale, options) when is_binary(datetime) do
    datetime
    |> TimeWrapper.parse!("{ISO:Extended}")
    |> format_datetime_to_paris(locale, options)
  end

  def format_datetime_to_paris(nil, _, _), do: ""

  @doc """
  Formats time of a date time for display.
  Input can be in any timezone, outputs is in Europe/Paris timezone.

  iex> format_time_to_paris(~U[2022-03-01 15:30:00+00:00], "fr")
  "16h30 Europe/Paris"
  iex> format_time_to_paris(~U[2022-03-01 15:30:00+00:00], "en")
  "16:30 Europe/Paris"
  iex> format_time_to_paris(~N[2022-03-01 15:30:00.0000], "en")
  "16:30 Europe/Paris"
  iex> format_time_to_paris("2022-03-01T15:30:00Z", "fr")
  "16h30 Europe/Paris"
  iex> format_time_to_paris("2022-03-01T15:30:00Z", "sauce tomate")
  "16h30 Europe/Paris"
  iex> format_time_to_paris("2022-03-01T15:30:00+01:00", "fr")
  "15h30 Europe/Paris"
  iex> format_time_to_paris("2022-03-01T15:30:00+01:00", "fr")
  "15h30 Europe/Paris"
  iex> format_time_to_paris("2022-03-01T15:30:09+01:00", "fr", with_seconds: true)
  "15:30:09 Europe/Paris"
  iex> format_time_to_paris("2022-03-01T15:30:00+00:00", "en")
  "16:30 Europe/Paris"
  iex> format_time_to_paris("2022-03-01T15:30:09+00:00", "en", with_seconds: true)
  "16:30:09 Europe/Paris"
  # right before daylight hour change
  iex> format_time_to_paris("2022-03-27T00:59+00:00", "fr")
  "01h59 Europe/Paris"
  # right after daylight hour change
  iex> format_time_to_paris("2022-03-27T01:00:00+00:00", "fr")
  "03h00 Europe/Paris"
  iex> format_time_to_paris("2022-03-27T01:00:00+00:00", "fr", no_timezone: true)
  "03h00"
  """
  def format_time_to_paris(dt, locale) do
    format_time_to_paris(dt, locale, [])
  end

  def format_time_to_paris(%DateTime{} = dt, locale, options) do
    format = get_localized_time_format(locale, options)
    format = if Keyword.get(options, :no_timezone), do: format, else: format <> " Europe/Paris"
    dt |> convert_to_paris_time() |> Calendar.strftime(format)
  end

  def format_time_to_paris(%NaiveDateTime{} = ndt, locale, options) do
    ndt
    |> convert_to_paris_time()
    |> format_time_to_paris(locale, options)
  end

  def format_time_to_paris(datetime, locale, options) when is_binary(datetime) do
    datetime
    |> TimeWrapper.parse!("{ISO:Extended}")
    |> format_time_to_paris(locale, options)
  end

  def format_time_to_paris(nil, _, _), do: ""

  @doc """
  Formats a duration in seconds to display, according to a locale.

  Supported locales: "fr" and "en".

  iex> format_duration(1, :en)
  "1 second"
  iex> format_duration(1, Transport.Cldr.Locale.new!("en"))
  "1 second"
  iex> format_duration(1, "en")
  "1 second"
  iex> format_duration(3, "en")
  "3 seconds"
  iex> format_duration(60, "en")
  "1 minute"
  iex> format_duration(61, "en")
  "1 minute and 1 second"
  iex> format_duration(65, "en")
  "1 minute and 5 seconds"
  iex> format_duration(120, "en")
  "2 minutes"
  iex> format_duration(125, "en")
  "2 minutes and 5 seconds"
  iex> format_duration(3601, "en")
  "1 hour and 1 second"
  iex> format_duration(3661, "en")
  "1 hour, 1 minute, and 1 second"

  iex> format_duration(1, :fr)
  "1 seconde"
  iex> format_duration(1, Transport.Cldr.Locale.new!("fr"))
  "1 seconde"
  iex> format_duration(1, "fr")
  "1 seconde"
  iex> format_duration(3, "fr")
  "3 secondes"
  iex> format_duration(60, "fr")
  "1 minute"
  iex> format_duration(61, "fr")
  "1 minute et 1 seconde"
  iex> format_duration(65, "fr")
  "1 minute et 5 secondes"
  iex> format_duration(120, "fr")
  "2 minutes"
  iex> format_duration(125, "fr")
  "2 minutes et 5 secondes"
  iex> format_duration(3601, "fr")
  "1 heure et 1 seconde"
  iex> format_duration(3661, "fr")
  "1 heure, 1 minute et 1 seconde"
  """
  @spec format_duration(pos_integer(), atom() | Cldr.LanguageTag.t()) :: binary()
  def format_duration(duration_in_seconds, locale) do
    locale = Cldr.Locale.new!(locale, Transport.Cldr)

    duration_in_seconds
    |> Cldr.Calendar.Duration.new_from_seconds()
    |> Cldr.Calendar.Duration.to_string!(locale: locale)
  end

  @spec convert_to_paris_time(DateTime.t() | NaiveDateTime.t()) :: DateTime.t()
  # TODO: add 2 DocTests to cover before. Then migrate to Timex-free call.
  def convert_to_paris_time(%DateTime{} = dt) do
    case Timex.Timezone.convert(dt, "Europe/Paris") do
      %Timex.AmbiguousDateTime{after: dt} -> dt
      %DateTime{} = dt -> dt
    end
  end

  def convert_to_paris_time(%NaiveDateTime{} = ndt) do
    ndt |> Timex.Timezone.convert("UTC") |> convert_to_paris_time()
  end

  defp get_localized_datetime_format("en" = locale, options) do
    "%Y-%m-%d at #{get_localized_time_format(locale, options)}"
  end

  defp get_localized_datetime_format(locale, options) do
    "%d/%m/%Y à #{get_localized_time_format(locale, options)}"
  end

  defp get_localized_time_format("en", options) do
    if Keyword.get(options, :with_seconds) do
      "%H:%M:%S"
    else
      "%H:%M"
    end
  end

  defp get_localized_time_format(_locale, options) do
    if Keyword.get(options, :with_seconds) do
      "%H:%M:%S"
    else
      "%Hh%M"
    end
  end
end
