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
  end

  def enrich(entry, unzip) do
    algorithm = :sha256

    checksum =
      unzip
      |> Unzip.file_stream!(entry.file_name)
      |> compute_checksum(algorithm)

    Map.put(entry, algorithm, checksum)
  end

  def compute_checksum(stream, algorithm) do
    stream
    |> Enum.reduce(:crypto.hash_init(algorithm), fn elm, acc -> :crypto.hash_update(acc, elm) end)
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
  end
end
