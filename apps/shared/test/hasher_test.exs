defmodule HasherTest do
  use ExUnit.Case

  test "hash by streaming a local file" do
    content = "coucou"
    hash = :sha256 |> :crypto.hash(content) |> Base.encode16() |> String.downcase()
    file_path = System.tmp_dir!() |> Path.join("coucou_file")
    File.write!(file_path, content)

    assert Hasher.get_file_hash(file_path) == hash
  end
end
