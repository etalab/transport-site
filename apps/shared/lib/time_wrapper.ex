defmodule TimeWrapper do
  def parse!(date_as_string, param = "{ISO:Extended}") do
    Timex.parse!(date_as_string, param)
  end

  def parse!(date_as_string, param = "{YYYY}{0M}{0D}") do
    Timex.parse!(date_as_string, param)
  end

  def parse!(datetime_as_string, param = "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} GMT") do
    Timex.parse!(datetime_as_string, param)
  end

  def diff(first, second, param = :hours) do
    Timex.diff(first, second, param)
  end

  def now() do
    Timex.now()
  end

  def shift(dt, months: months) do
    Timex.shift(dt, months: months)
  end

  def convert(dt, "UTC") do
    Timex.Timezone.convert(dt, "UTC")
  end

  def convert_to_paris_time(dt) do
    case Timex.Timezone.convert(dt, "Europe/Paris") do
      %Timex.AmbiguousDateTime{after: dt} -> dt
      %DateTime{} = dt -> dt
    end
  end
end
