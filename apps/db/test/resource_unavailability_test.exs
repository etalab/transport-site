defmodule DB.ResourceUnavailabilityTest do
  use DB.DatabaseCase, cleanup: []
  alias DB.{Repo, ResourceUnavailability}
  import DB.Factory

  describe "ongoing_unavailability" do
    test "it works" do
      # No unavailabilities
      resource = insert(:resource)
      assert is_nil(ResourceUnavailability.ongoing_unavailability(resource))

      # An ongoing unavailability
      %{id: resource_unavailability_id} = insert(:resource_unavailability, resource: resource, start: hours_ago(5))
      assert resource_unavailability_id == ResourceUnavailability.ongoing_unavailability(resource).id

      # Closing the ongoing unavailability
      ResourceUnavailability
      |> Repo.get_by(resource_id: resource.id)
      |> Ecto.Changeset.change(%{end: hours_ago(1)})
      |> Repo.update()

      assert is_nil(ResourceUnavailability.ongoing_unavailability(resource))

      # It's properly scoped by resource
      insert(:resource_unavailability, resource: build(:resource), start: hours_ago(5))
      assert is_nil(ResourceUnavailability.ongoing_unavailability(resource))
    end

    test "with multiple unavailabilities" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(10), end: hours_ago(9))
      %{id: resource_unavailability_id} = insert(:resource_unavailability, resource: resource, start: hours_ago(5))

      assert resource_unavailability_id == ResourceUnavailability.ongoing_unavailability(resource).id
    end
  end

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours * 60 * 60, :second) |> DateTime.truncate(:second)
  end
end
