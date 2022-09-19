defmodule Transport.CSVDocumentsTest do
  use ExUnit.Case

  test "ensures that all referenced logos do exist" do
    Transport.CSVDocuments.reusers()
    |> Enum.each(fn %{"image" => image} ->
      path =
        __DIR__
        |> Path.join("/../../client/images/logos")
        |> Path.join(image)

      assert File.exists?(path)
    end)
  end

  test "CSV for ZFE looks okay" do
    zfe = Transport.CSVDocuments.zfe_ids()

    # No duplicates
    assert zfe |> Enum.map(& &1["code"]) |> Enum.uniq() |> Enum.count() == Enum.count(zfe)
    assert zfe |> Enum.map(& &1["siren"]) |> Enum.uniq() |> Enum.count() == Enum.count(zfe)
    # No empty code
    assert zfe |> Enum.map(& &1["code"]) |> Enum.filter(&is_nil(&1)) |> Enum.empty?()
  end
end
