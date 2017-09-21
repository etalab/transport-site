defmodule Transport.Datagouvfr.ClientTest do
  use ExUnit.Case, async: true
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  alias Transport.Datagouvfr.Client

  doctest Client

  test "get a lot of organizations" do
    use_cassette "client/all-0" do
      assert {:ok, data} = Client.organizations
      assert data |> Map.get("data") |> List.first |> Map.get("name") =~ "Ministère de l'Intérieur"
    end
  end

  test "get organization by term" do
    use_cassette "client/search-1" do
      assert {:ok, data} = Client.organizations(%{"q" => "Reims"})
      assert data |> Map.get("data") |> List.first |> Map.get("name") =~ "Montagne de Reims"
    end
  end
end
