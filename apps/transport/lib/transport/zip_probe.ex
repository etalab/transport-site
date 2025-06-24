defmodule Transport.ZipProbe do
  @moduledoc """
  Utility module to probe/detect ZIP files.
  """

  @doc """
  Cheap heuristic to detect likely ZIP content based on the first four bytes of the file.

  Ref: https://en.wikipedia.org/wiki/ZIP_(file_format)

  ## Examples

      iex> likely_zip_content?("PK\x03\x04" <> "some content")
      true

      iex> likely_zip_content?("PK\x05\x06" <> "foobar")
      true

      iex> likely_zip_content?("some content")
      false
  """
  def likely_zip_content?(<<?P, ?K, a, b, _rest::binary>>) when a < 0x10 and b < 0x10, do: true
  def likely_zip_content?(_), do: false
end
