defmodule XMLHelper do
  @moduledoc """
  A bit of tooling to help work with XML
  """
  def unnamespace(tag), do: tag |> String.split(":") |> List.last()
end
