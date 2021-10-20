defmodule Transport.UrlExtractorDocTest do
  use ExUnit.Case, async: true
  alias Opendatasoft.UrlExtractor
  import Mox
  doctest UrlExtractor

  test "get urls in CSV file" do
    Transport.HTTPoison.Mock |> expect(:head, fn _url -> %HTTPoison.Response{} end)

    res =
      [{"name,file\ntoulouse,http", %{"id" => "bob"}}, {"stop,lon,lat\n1,48.8,2.3", %{"id" => "bobette"}}]
      |> UrlExtractor.get_resources_with_url_from_csv()

    assert res == {:ok, [%{"url" => "http", "title" => "http", "id" => "bob"}]}
  end

  test "get urls in CSV file : no url available" do
    Transport.HTTPoison.Mock |> expect(:head, fn _url -> %HTTPoison.Response{} end)

    assert UrlExtractor.get_resources_with_url_from_csv([{"stop,lon,lat\\n1,48.8,2.3", %{"id" => "bob"}}]) ==
             {:error, "No url found"}
  end
end
