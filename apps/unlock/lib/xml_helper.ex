defmodule XMLHelper do
  def unnamespace(tag), do: tag |> String.split(":") |> List.last()
end
