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

  @doc """
  Check whether an entry inside a ZIP archive is itself likely ZIP content.

  Reads bytes from the entry's stream until at least 4 bytes have been collected
  (the size of the ZIP magic signature), then delegates to [`likely_zip_content?/1`][1].
  Returns `false` on any read error or if fewer than 4 bytes are available.

  [1]: Transport.ZipProbe.likely_zip_content?/1

  ## Examples

      iex> ZipCreator.with_tmp_zip([{"resource.xml", "<PublicationDelivery />"}], fn tmp_path ->
      ...>   zip = Unzip.LocalFile.open(tmp_path)
      ...>   {:ok, unzip} = Unzip.new(zip)
      ...>
      ...>   # The entry contains XML, not ZIP data
      ...>   assert Transport.ZipProbe.nested_zip_content?(unzip, "resource.xml") == false
      ...>
      ...>   Unzip.LocalFile.close(zip)
      ...> end)
      :ok
  """
  def nested_zip_content?(unzip, file_name) do
    unzip
    |> Unzip.file_stream!(file_name, chunk_size: 4)
    |> Enum.reduce_while(<<>>, fn chunk, acc ->
      acc = acc <> IO.iodata_to_binary(chunk)
      if byte_size(acc) >= 4, do: {:halt, binary_part(acc, 0, 4)}, else: {:cont, acc}
    end)
    |> likely_zip_content?()
  rescue
    _ -> false
  end
end
