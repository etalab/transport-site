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
end
