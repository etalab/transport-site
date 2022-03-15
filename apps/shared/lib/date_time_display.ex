defmodule Shared.DateTimeDisplay do
  @moduledoc """
  A module to have a coherent display of dates and times accross the website.
  The goal is to show date times for Europe/Paris timezone to our users.
  """
  alias Timex.Format.DateTime.Formatter

  @doc """
  Formats a date to display depending on the locale

  iex> format_date(~D[2022-03-01], "fr")
  "01/03/2022"
  iex> format_date(~D[2022-03-01], "en")
  "2022-03-01"
  iex> format_date("2022-03-01", "fr")
  "01/03/2022"
  iex> format_date("2022-03-01", "en")
  "2022-03-01"
  """
  @spec format_date(binary | Date.t(), binary() | nil) :: binary
  def format_date(%Date{} = date, "fr"), do: Calendar.strftime(date, "%d/%m/%Y")
  def format_date(%Date{} = date, nil), do: format_date(date, "fr")
  def format_date(%Date{} = date, "en"), do: Calendar.strftime(date, "%Y-%m-%d")

  def format_date(date, locale) when is_binary(date) do
    date |> Date.from_iso8601!() |> format_date(locale)
  end

  def format_date(nil, _), do: ""

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
  iex> format_datetime_to_paris("2022-03-01T15:30:00+01:00", "fr")
  "01/03/2022 à 15h30 Europe/Paris"
  iex> format_datetime_to_paris("2022-03-01T15:30:00+00:00", "en")
  "2022-03-01 at 16:30 Europe/Paris"
  """
  def format_datetime_to_paris(%DateTime{} = dt, "fr") do
    dt
    |> convert_to_paris_time()
    |> Calendar.strftime("%d/%m/%Y à %Hh%M Europe/Paris")
  end

  def format_datetime_to_paris(%DateTime{} = dt, nil) do
    format_datetime_to_paris(dt, "fr")
  end

  def format_datetime_to_paris(%DateTime{} = dt, "en") do
    dt
    |> convert_to_paris_time()
    |> Calendar.strftime("%Y-%m-%d at %H:%M Europe/Paris")
  end

  def format_datetime_to_paris(%NaiveDateTime{} = ndt, locale) do
    ndt
    |> convert_to_paris_time()
    |> format_datetime_to_paris(locale)
  end

  def format_datetime_to_paris(datetime, locale) when is_binary(datetime) do
    datetime
    |> Timex.parse!("{ISO:Extended}")
    |> format_datetime_to_paris(locale)
  end

  def format_datetime_to_paris(nil, _), do: ""

  defp convert_to_paris_time(%DateTime{} = dt), do: dt |> Timex.Timezone.convert("Europe/Paris")
  defp convert_to_paris_time(%NaiveDateTime{} = ndt), do: ndt |> Timex.Timezone.convert("Europe/Paris")

  @doc """
  Converts a binary naive date time to a binary date time having the Paris timezone.
  Output formatting is ISO 8601

  iex> format_naive_datetime_to_paris_tz("2022-03-01T15:30:00")
  "2022-03-01T15:30:00+01:00"
  """
  @spec format_naive_datetime_to_paris_tz(nil | binary) :: binary
  def format_naive_datetime_to_paris_tz(nil), do: ""

  def format_naive_datetime_to_paris_tz(naive_datetime) do
    naive_datetime
    |> Timex.parse!("{ISO:Extended}")
    |> convert_to_paris_time()
    |> Formatter.format!("{ISO:Extended}")
  end
end
