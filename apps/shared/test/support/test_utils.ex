defmodule Transport.Test.TestUtils do
  @moduledoc """
  Some useful functions for testing
  """

  def ensure_no_tmp_files!(file_prefix) do
    tmp_files = System.tmp_dir!() |> File.ls!()

    ExUnit.Assertions.assert(
      tmp_files |> Enum.filter(fn f -> String.starts_with?(f, file_prefix) end) |> Enum.empty?(),
      "tmp files found in #{System.tmp_dir!()}"
    )
  end

  def zip_metadata do
    # Metadata for shared/test/validation/gtfs.zip
    [
      %{
        "compressed_size" => 41,
        "file_name" => "ExportService.checksum.md5",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "f0c7216411dec821330ffbebf939bfe73a50707f5e443795a122ec7bef37aa16",
        "uncompressed_size" => 47
      },
      %{
        "compressed_size" => 115,
        "file_name" => "agency.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "548de694a86ab7d6ac0cd3535b0c3b8bffbabcc818e8d7f5a4b8f17030adf617",
        "uncompressed_size" => 143
      },
      %{
        "compressed_size" => 179,
        "file_name" => "calendar.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "390c446ee520bc63c49f69da16d4fe08bceb0511ff19f8491315b739a60f61d6",
        "uncompressed_size" => 495
      },
      %{
        "compressed_size" => 215,
        "file_name" => "calendar_dates.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "4779cd26ddc1d44c8544cb1be449b0f6b48b65fe8344861ee46bcfa3787f9ba7",
        "uncompressed_size" => 1197
      },
      %{
        "compressed_size" => 82,
        "file_name" => "routes.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "27eadc95f783e85c352c9b6b75cc896d9afd236c58c332597a1fac1c14c1f855",
        "uncompressed_size" => 102
      },
      %{
        "compressed_size" => 1038,
        "file_name" => "stop_times.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "dc452a69b86b07841d5de49705ceea22340d639eebfd6589b379d1b38b9b9da1",
        "uncompressed_size" => 5128
      },
      %{
        "compressed_size" => 251,
        "file_name" => "stops.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "2685fb16434b396f277c7ad593b609574ed01592b48de7001c53beb36b926eca",
        "uncompressed_size" => 607
      },
      %{
        "compressed_size" => 71,
        "file_name" => "transfers.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "269d48635624c4b46968cb649fc5a5a1c2224c2dac1670aa6082516ca0c50f59",
        "uncompressed_size" => 102
      },
      %{
        "compressed_size" => 378,
        "file_name" => "trips.txt",
        "last_modified_datetime" => "2017-02-16T05:01:12",
        "sha256" => "dd79f0fb8d2fd0a70cc75f49c5f2cae56b9b2ef83670992d6b195e9806393c24",
        "uncompressed_size" => 2864
      }
    ]
  end
end
