defmodule HasherTest do
  use ExUnit.Case, async: true
  import Transport.Test.TestUtils, only: [zip_metadata: 0]

  test "hash by streaming a local file" do
    content = "coucou"
    hash = :sha256 |> :crypto.hash(content) |> Base.encode16() |> String.downcase()
    file_path = System.tmp_dir!() |> Path.join("coucou_file")
    File.write!(file_path, content)

    assert Hasher.get_file_hash(file_path) == hash
  end

  test "hashing zip metadata" do
    expected_hash = "cb4702410007f184c708dab708152608673e822c04a228d6c1a5d923be661021"
    assert Hasher.zip_hash(zip_metadata()) == expected_hash
    assert Hasher.zip_hash(Enum.shuffle(zip_metadata())) == expected_hash
    refute Hasher.zip_hash(zip_metadata() |> Enum.take(2)) == expected_hash
  end
end
