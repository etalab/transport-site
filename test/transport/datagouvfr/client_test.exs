defmodule Transport.Datagouvfr.ClientTest do
  use TransportWeb.ConnCase, async: false # smell
  use TransportWeb.ExternalCase # smell
  alias Transport.Datagouvfr.Client
  alias Transport.Datagouvfr.Client.Organizations

  doctest Client

  test "get a lot of organizations" do
    use_cassette "client/all-0" do
      assert {:ok, data} = Organizations.get(build_conn())
      assert data |> Map.get("data") |> List.first |> Map.get("name") =~ "Ministère de l'Intérieur"
    end
  end

  test "get organization by term" do
    use_cassette "client/search-1" do
      assert {:ok, data} = Organizations.get(build_conn(), %{"q" => "Reims"})
      assert data |> Map.get("data") |> List.first |> Map.get("name") =~ "Montagne de Reims"
    end
  end
end
