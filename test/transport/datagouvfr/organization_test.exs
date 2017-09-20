defmodule Transport.Datagouvfr.OrganizationTest do
  use ExUnit.Case, async: true
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  alias Transport.Datagouvfr.Organization

  doctest Organization

  test "get a lot of organizations" do
    use_cassette "organization/all-0" do
      assert {:ok, data} = Organization.all
      assert data |> List.first |> Map.get("name") =~ "Ministère de l'Intérieur"
    end
  end

  test "get organization by term" do
    use_cassette "organization/search-1" do
      assert {:ok, data} = Organization.search("Reims")
      assert data |> List.first |> Map.get("name") =~ "Montagne de Reims"
    end
  end
end
