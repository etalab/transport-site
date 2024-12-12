defmodule TimeWrapper do
  def parse!(date_as_string, param = "{ISO:Extended}") do
    Timex.parse!(date_as_string, param)
  end
end
