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
end
