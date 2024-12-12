defmodule TimeWrapper do
  def parse!(date_as_string, param = "{ISO:Extended}") do
    Timex.parse!(date_as_string, param)
  end

  def parse!(date_as_string, param = "{YYYY}{0M}{0D}") do
    Timex.parse!(date_as_string, param)
  end
end
