defmodule Transport.Test.FileStreamUtils do
  @moduledoc """
  Shared tools to mox unzip calls during tests.
  """
  import ExUnit.Assertions
  import Mox

  def setup_get_file_stream_mox(zip_filename) do
    # NOTE: it will be possible to reuse common code from Transport.Unzip.S3 in there
    Transport.Unzip.S3.Mock
    |> expect(:get_file_stream, fn file_in_zip, zip_file, bucket ->
      # from payload
      assert zip_file == zip_filename
      # from config
      assert bucket == "transport-data-gouv-fr-resource-history-test"

      # stub with a local file
      path = "#{__DIR__}/../fixture/files/gtfs_import.zip"
      zip_file = Unzip.LocalFile.open(path)
      {:ok, unzip} = Unzip.new(zip_file)
      Unzip.file_stream!(unzip, file_in_zip)
    end)
  end
end
