defmodule Transport.Datagouvfr.Client.OrganizationsTest do
  use TransportWeb.ConnCase, async: false # smell
  use TransportWeb.ExternalCase # smell
  alias Transport.Datagouvfr.Client
  alias Transport.Datagouvfr.Client.Organizations

  doctest Client

  test "get many organizations" do
    use_cassette "client/organizations/many-0" do
      assert {:ok, data} = Organizations.get(build_conn())
      assert data |> Enum.count() > 0
    end
  end

  test "search organizations" do
    use_cassette "client/organizations/search-1" do
      assert {:ok, data} = Organizations.get(build_conn(), %{:q => "angers"})
      assert %{"data" => [%{"id" => id}|_]} = data
      assert id == "538346d6a3a72906c7ec5c36"
    end
  end

  test "get one organization" do
    use_cassette "client/organizations/one-3" do
      assert {:ok, data} = Organizations.get(build_conn(), "538346d6a3a72906c7ec5c36")
      assert %{"id" => id} = data
      assert id == "538346d6a3a72906c7ec5c36"
    end
  end

  test "get one organization with datasets" do
    use_cassette "client/organizations/with-datasets-3" do
      assert {:ok, data} = Organizations.get(build_conn(), "538346d6a3a72906c7ec5c36", :with_datasets)
      assert %{"id" => id} = data
      assert id == "538346d6a3a72906c7ec5c36"
      assert data |> Map.get("datasets") |> Enum.count() > 0
    end
  end
end
