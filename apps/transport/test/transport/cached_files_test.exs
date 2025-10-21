defmodule Transport.CachedFilesTest do
  use ExUnit.Case

  test "CSV for ZFE looks okay" do
    zfe = Transport.CachedFiles.zfe_ids()

    # No duplicates
    assert zfe |> Enum.map(& &1["code"]) |> Enum.uniq() |> Enum.count() == Enum.count(zfe)
    assert zfe |> Enum.map(& &1["siren"]) |> Enum.uniq() |> Enum.count() == Enum.count(zfe)
    # No empty code
    assert zfe |> Enum.map(& &1["code"]) |> Enum.filter(&is_nil(&1)) |> Enum.empty?()
  end

  test "can load CSV for GBFS operators" do
    operators = Transport.CachedFiles.gbfs_operators() |> Enum.map(& &1["operator"]) |> Enum.uniq()

    assert "JC Decaux" in operators
    assert "Cykleo" in operators

    # Check `operator` values. Prevent typos and ensure unique values.
    # Detect things like `Cykleo` VS `Cykléo`.
    for x <- operators, y <- operators, x != y do
      error_message = "#{x} and #{y} look too similar. Is it the same operator?"
      assert String.jaro_distance(x, y) <= 0.75 || distinct_operators?(x, y), error_message
    end

    # Check `url` values. Make sure there is at most a single match per GBFS feed.
    # We can't have in the file `example.com` and `example.com/city` for example.
    urls = Transport.CachedFiles.gbfs_operators() |> Enum.map(& &1["url"])

    for x <- urls, y <- urls, x != y do
      refute String.contains?(x, y), "#{x} is contained #{y}. A GBFS feed can only match for a single URL."
    end
  end

  def distinct_operators?(x, y) do
    [
      ["Citiz", "Citybike"]
    ]
    |> Enum.member?(Enum.sort([x, y]))
  end

  test "can load static IRVE schema" do
    irve_schema = Transport.CachedFiles.static_irve_schema()
    assert irve_schema["name"] == "schema-irve-statique"
  end
end
