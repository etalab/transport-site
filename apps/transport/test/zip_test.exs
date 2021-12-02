defmodule Transport.ZipMetaDataExtractorTest do
  use ExUnit.Case, async: true

  test "extract! with a valid zip" do
    path = "#{__DIR__}/../../shared/test/validation/gtfs.zip"
    results = Transport.ZipMetaDataExtractor.extract!(path)

    assert 9 == Enum.count(results)

    assert %{
             compressed_size: 251,
             file_name: "stops.txt",
             last_modified_datetime: ~N[2017-02-16 05:01:12],
             sha256: "2685fb16434b396f277c7ad593b609574ed01592b48de7001c53beb36b926eca",
             uncompressed_size: 607
           } == results |> Enum.find(fn e -> e.file_name == "stops.txt" end)

    assert %{
             compressed_size: 378,
             file_name: "trips.txt",
             last_modified_datetime: ~N[2017-02-16 05:01:12],
             sha256: "dd79f0fb8d2fd0a70cc75f49c5f2cae56b9b2ef83670992d6b195e9806393c24",
             uncompressed_size: 2864
           } == results |> Enum.find(fn e -> e.file_name == "trips.txt" end)
  end

  test "extract! with a non existing file" do
    assert_raise MatchError, fn ->
      Transport.ZipMetaDataExtractor.extract!("foo")
    end
  end
end
