defmodule TransportWeb.ReuserSpaceViewTest do
  use ExUnit.Case, async: true
  import TransportWeb.ReuserSpaceView

  @google_maps_org_id "63fdfe4f4cd1c437ac478323"

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "data_sharing_pilot?" do
    test "contact is not a member of an eligible organization" do
      dataset = %DB.Dataset{type: "public-transit", custom_tags: ["repartage_donnees"]}
      contact = %DB.Contact{organizations: []}
      refute data_sharing_pilot?(dataset, contact)
    end

    test "dataset does not have the required tag" do
      dataset = %DB.Dataset{type: "public-transit", custom_tags: []}
      contact = %DB.Contact{organizations: [%DB.Organization{id: @google_maps_org_id}]}
      refute data_sharing_pilot?(dataset, contact)
    end

    test "dataset is eligible for contact" do
      dataset = %DB.Dataset{type: "public-transit", custom_tags: ["repartage_donnees"]}
      contact = %DB.Contact{organizations: [%DB.Organization{id: @google_maps_org_id}]}
      assert data_sharing_pilot?(dataset, contact)
    end
  end
end
