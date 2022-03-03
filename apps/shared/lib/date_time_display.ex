defmodule Shared.DateTimeDisplay do
  @moduledoc """
  A module to have a coherent display of dates and times accross the website
  """

  @doc """
  Formats a date to display depending on the locale

  iex> format_date(~D[2022-03-01], "fr")
  "01/03/2022"
  iex> format_date(~D[2022-03-01], "en")
  "03/01/2022"
  iex> format_date("2022-03-01", "fr")
  "01/03/2022"
  iex> format_date("2022-03-01", "en")
  "03/01/2022"
  """
  @spec format_date(binary | Date.t(), <<_::16>>) :: binary
  def format_date(%Date{} = date, "fr"), do: Calendar.strftime(date, "%d/%m/%Y")

  def format_date(%Date{} = date, "en"), do: Calendar.strftime(date, "%m/%d/%Y")

  def format_date(date, locale) when is_binary(date) do
    date |> Date.from_iso8601!() |> format_date(locale)
  end

  @doc """
  Display a date from a DateTime

  iex> format_datetime_to_date(~U[2022-03-01T15:00:00Z], "fr")
  "01/03/2022"
  iex> format_datetime_to_date(~U[2022-03-01T15:00:00Z], "en")
  "03/01/2022"
  """
  def format_datetime_to_date(%DateTime{} = dt, locale) do
    DateTime.to_date(dt) |> format_date(locale)
  end
end
