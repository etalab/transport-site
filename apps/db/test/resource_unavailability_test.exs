defmodule DB.ResourceUnavailabilityTest do
  use DB.DatabaseCase, cleanup: []
  alias DB.{Repo, ResourceUnavailability}
  import DB.Factory

  doctest DB.ResourceUnavailability, import: true

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
      |> Repo.update!()

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

  describe "availability_over_last_days and unavailabilities_over_last_days" do
    test "with no unavailabilities" do
      resource = insert(:resource)

      assert %{hours: 0, nb_periods: 0, resource_id: resource.id} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert 100 == ResourceUnavailability.availability_over_last_days(resource, 1)
    end

    test "with an unavailabily starting before" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(25))

      assert %{hours: 24, resource_id: resource.id, nb_periods: 1} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert 0 == ResourceUnavailability.availability_over_last_days(resource, 1)
    end

    test "with an ongoing unavailability starting in period" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(5))

      assert %{hours: 5, resource_id: resource.id, nb_periods: 1} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 100 - 5 / 24 * 100, 0.1
    end

    test "with an unavailabiliy starting before and ending in period" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(26), end: hours_ago(22))

      assert %{hours: 2, resource_id: resource.id, nb_periods: 1} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 100 - 2 / 24 * 100, 0.1
    end

    test "with multiple unavailabilities" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(26), end: hours_ago(22))
      insert(:resource_unavailability, resource: resource, start: hours_ago(2), end: hours_ago(1))

      assert %{hours: 3, resource_id: resource.id, nb_periods: 2} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert 87.5 == ResourceUnavailability.availability_over_last_days(resource, 1)
    end

    test "scopes to specific resource" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(10), end: hours_ago(8))
      insert(:resource_unavailability, resource: insert(:resource), start: hours_ago(10), end: hours_ago(8))

      assert %{hours: 2, resource_id: resource.id, nb_periods: 1} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)
    end

    test "computes appropriate ratio" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(7), end: hours_ago(1))

      assert %{hours: 6, resource_id: resource.id, nb_periods: 1} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 100 - 6 / 24 * 100, 0.1
      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 2), 100 - 6 / 48 * 100, 0.1
    end
  end

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours * 60 * 60, :second) |> DateTime.truncate(:second)
  end
end
