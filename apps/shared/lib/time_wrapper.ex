defmodule TimeWrapper do
  def parse!(date_as_string, "{ISO:Extended}" = param) do
    Timex.parse!(date_as_string, param)
  end

  def parse!(date_as_string, "{YYYY}{0M}{0D}" = param) do
    Timex.parse!(date_as_string, param)
  end

  # TODO: remove completely. This is rfc2822 ; Plug encodes it, but there is no built-in decoder.
  def parse!(datetime_as_string, "{WDshort}, {D} {Mshort} {YYYY} {h24}:{m}:{s} GMT" = param) do
    Timex.parse!(datetime_as_string, param)
  end

  def diff(first, second, :hours = param) do
    Timex.diff(first, second, param)
  end

  def now do
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
