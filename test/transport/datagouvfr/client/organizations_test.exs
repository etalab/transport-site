defmodule Transport.Datagouvfr.Client.OrganizationsTest do
  use TransportWeb.ConnCase, async: false # smell
  use TransportWeb.ExternalCase # smell
  alias Transport.Datagouvfr.Client

  doctest Client

  test "get many organizations" do
    use_cassette "client/organizations/many-0" do
      assert {:ok, data} = Client.Organizations.get(build_conn())
      assert data |> Enum.count() > 0
    end
  end

  test "search organizations" do
    use_cassette "client/organizations/search-1" do
      assert {:ok, data} = Client.Organizations.get(build_conn(), %{:q => "angers"})
      assert %{"data" => [%{"slug" => slug}|_]} = data
      assert slug == "angers-loire-metropole"
    end
  end

  test "get one organization" do
    use_cassette "client/organizations/one-3" do
      assert {:ok, data} = Client.Organizations.get(build_conn(), "angers-loire-metropole")
      assert %{"slug" => slug} = data
      assert slug == "angers-loire-metropole"
    end
  end

  test "get one organization with datasets" do
    use_cassette "client/organizations/with-datasets-3" do
      assert {:ok, data} = Client.Organizations.get(build_conn(), "angers-loire-metropole", :with_datasets)
      assert %{"slug" => slug} = data
      assert slug == "angers-loire-metropole"
      assert data |> Map.get("datasets") |> Enum.count() > 0
    end
  end
end
