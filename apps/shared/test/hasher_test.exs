defmodule HasherTest do
  use ExUnit.Case, async: true
  import Transport.Test.TestUtils, only: [zip_metadata: 0]

  @expected_hash "cb4702410007f184c708dab708152608673e822c04a228d6c1a5d923be661021"

  test "hash by streaming a local file" do
    content = "coucou"
    hash = :sha256 |> :crypto.hash(content) |> Base.encode16() |> String.downcase()
    file_path = System.tmp_dir!() |> Path.join("coucou_file")
    File.write!(file_path, content)

    assert Hasher.get_file_hash(file_path) == hash
  end

  describe "hashing zip metadata" do
    test "it works" do
      assert Hasher.zip_hash(zip_metadata()) == @expected_hash
    end

    test "can shuffle zip files" do
      assert Hasher.zip_hash(Enum.shuffle(zip_metadata())) == @expected_hash
    end

    test "can handle keys with atoms or strings" do
      assert Map.has_key?(zip_metadata() |> Enum.random(), "sha256")
      zip_metadata_atom_keys = zip_metadata() |> Enum.map(&to_atom_keys(&1))
      assert Map.has_key?(zip_metadata_atom_keys |> Enum.random(), :sha256)
      assert Hasher.zip_hash(zip_metadata_atom_keys) == @expected_hash
    end

    test "hash changes" do
      refute Hasher.zip_hash(zip_metadata() |> Enum.take(2)) == @expected_hash
    end
  end

  defp to_atom_keys(map) do
    map |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
  end
end
