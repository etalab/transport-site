defmodule Transport.ZipMetaDataExtractor do
  @moduledoc """
  A module to extract the metadata out of a zip file on disk. It relies on `unzip`
  which is able to stream the content of each file, allowing us to easily compute a
  SHA256 for each entry.
  """

  def extract!(file) do
    zip_file = Unzip.LocalFile.open(file)
    {:ok, unzip} = Unzip.new(zip_file)
    # NOTE: `unzip.cd_list` contains crc + filenames & more info, if needed
    unzip
    |> Unzip.list_entries()
    |> Enum.map(&enrich(&1, unzip))
    |> Enum.map(fn m -> keep_keys(m, keys()) end)
  end

  def keep_keys(map, keys) do
    Enum.into(keys, %{}, fn key -> {key, Map.fetch!(map, key)} end)
  end

  defp keys do
    [
      :compressed_size,
      :file_name,
      :last_modified_datetime,
      :sha256,
      :uncompressed_size
    ]
  end

  def enrich(entry, unzip) do
    algorithm = :sha256

    checksum =
      unzip
      |> Unzip.file_stream!(entry.file_name)
      |> Hasher.compute_checksum(algorithm)

    entry |> Map.put(algorithm, checksum)
  end
end
