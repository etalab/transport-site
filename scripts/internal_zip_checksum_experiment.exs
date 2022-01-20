Mix.install([
  {:req, "~> 0.2.0"},
  {:unzip, "~> 0.6.0"}
])

defmodule ZipMetaDataExtractor do
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

defmodule DemoDownload do
  @moduledoc """
  A quick helper to download a given file on disk
  """
  def download do
    IO.puts("Starting....")

    url = "https://zenbus.net/gtfs/static/download.zip?dataset=fontenay"

    response =
      Req.build(:get, url)
      |> Req.run!()

    IO.inspect(response, IEx.inspect_opts())

    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    filename = "save-#{timestamp}.zip"
    IO.puts("Writing #{filename}...")
    File.write!(filename, response.body)
  end
end

# Uncomment and run twice to get files with different external checksums,
# but same content inside
# DemoDownload.download()

Path.wildcard("save-*.zip")
|> Enum.map(&ZipMetaDataExtractor.extract!/1)
|> IO.inspect(IEx.inspect_opts())
