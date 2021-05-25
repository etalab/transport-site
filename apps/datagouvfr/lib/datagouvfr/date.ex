defmodule Datagouvfr.DgDate do
  @moduledoc """
  A module to handle and manipulate dates coming from data.gouv.fr
  The goal is to create a clear boundary between our code and datagouvfr internal handling of dates
  In the future, all dates coming from data.gouv should be handled with this module
  Data.gouv API contains iso8601 local datetimes (no timezone specified), but its documentation says that tz should be specified.
  """

  def truncate(dg_datetime, precision), do: NaiveDateTime.truncate(dg_datetime, precision)

  def from_iso8601(string_datetime, calendar \\ Calendar.ISO) do
    NaiveDateTime.from_iso8601(string_datetime, calendar)
  end

  def latest_dg_datetime(date1, date2) do
    case NaiveDateTime.compare(date1, date2) do
      :lt -> date2
      _ -> date1
    end
  end

  def diff(date1, date2), do: NaiveDateTime.diff(date1, date2)
end
