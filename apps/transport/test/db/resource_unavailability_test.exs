defmodule DB.ResourceUnavailabilityTest do
  use ExUnit.Case, async: true
  alias DB.{Repo, ResourceUnavailability}
  import DB.Factory

  doctest DB.ResourceUnavailability, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

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
      %{id: resource_id} = resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(5))

      assert %{hours: hours, resource_id: ^resource_id, nb_periods: 1} =
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta hours, 5, 0.1

      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 100 - 5 / 24 * 100, 0.1
    end

    test "with an unavailability starting before and ending in period" do
      %{id: resource_id} = resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(26), end: hours_ago(22))

      assert %{hours: hours, resource_id: ^resource_id, nb_periods: 1} =
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta hours, 2, 0.1

      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 100 - 2 / 24 * 100, 0.1
    end

    test "with multiple unavailabilities" do
      %{id: resource_id} = resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(26), end: hours_ago(22))
      insert(:resource_unavailability, resource: resource, start: hours_ago(2), end: hours_ago(1))

      assert %{hours: hours, resource_id: ^resource_id, nb_periods: 2} =
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta hours, 3, 0.1

      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 87.5, 0.01
    end

    test "with an unavailability starting before and ending before period" do
      resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(72), end: hours_ago(25))

      assert %{hours: 0, resource_id: resource.id, nb_periods: 0} ==
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert ResourceUnavailability.availability_over_last_days(resource, 1) <= 100
      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 100, 0.01
    end

    test "scopes to specific resource" do
      %{id: resource_id} = resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(10), end: hours_ago(8))
      insert(:resource_unavailability, resource: insert(:resource), start: hours_ago(10), end: hours_ago(8))

      assert %{hours: hours, resource_id: ^resource_id, nb_periods: 1} =
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta hours, 2, 0.01
    end

    test "computes appropriate ratio" do
      %{id: resource_id} = resource = insert(:resource)
      insert(:resource_unavailability, resource: resource, start: hours_ago(7), end: hours_ago(1))

      assert %{hours: hours, resource_id: ^resource_id, nb_periods: 1} =
               ResourceUnavailability.unavailabilities_over_last_days(resource, 1)

      assert_in_delta hours, 6, 0.01

      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 1), 100 - 6 / 24 * 100, 0.1
      assert_in_delta ResourceUnavailability.availability_over_last_days(resource, 2), 100 - 6 / 48 * 100, 0.1
    end

    test "compute bucketed availability" do
      resource = insert(:resource)

      today = DateTime.utc_now() |> DateTime.to_date()
      two_days_ago = Date.add(today, -2)
      three_days_ago = Date.add(today, -3)
      four_days_ago = Date.add(today, -4)

      three_days_ago_midnight = three_days_ago |> DateTime.new!(~T[00:00:00.00])

      insert(:resource_unavailability,
        resource: resource,
        start: three_days_ago_midnight |> add_hours(-2),
        end: three_days_ago_midnight |> add_hours(2)
      )

      insert(:resource_unavailability,
        resource: resource,
        start: three_days_ago_midnight |> add_hours(3),
        end: three_days_ago_midnight |> add_hours(4)
      )

      uptime = ResourceUnavailability.uptime_per_day(resource, 30)

      uptime_two_days_ago =
        uptime |> Enum.filter(fn d -> d["day"] == two_days_ago end) |> Enum.at(0) |> Map.fetch!("uptime")

      uptime_three_days_ago =
        uptime |> Enum.filter(fn d -> d["day"] == three_days_ago end) |> Enum.at(0) |> Map.fetch!("uptime")

      uptime_four_days_ago =
        uptime |> Enum.filter(fn d -> d["day"] == four_days_ago end) |> Enum.at(0) |> Map.fetch!("uptime")

      assert uptime_two_days_ago == 1
      assert_in_delta(uptime_four_days_ago, 22 / 24, 0.001)
      assert_in_delta(uptime_three_days_ago, 21 / 24, 0.001)
    end

    test "uptime_per_day over multiple days with an ongoing downtime" do
      resource = insert(:resource)

      utc_now = DateTime.utc_now()
      today_as_date = utc_now |> DateTime.to_date()
      downtime_in_hours = 3

      insert(:resource_unavailability,
        resource: resource,
        start: utc_now |> add_hours(-1 * downtime_in_hours),
        end: nil
      )

      uptime = ResourceUnavailability.uptime_per_day(resource, 30)
      uptime_today = uptime |> Enum.filter(&(&1["day"] == today_as_date)) |> Enum.at(0) |> Map.fetch!("uptime")

      seconds_since_midnight = DateTime.diff(today_as_date |> DateTime.new!(~T[00:00:00.00]), utc_now) * -1

      assert_in_delta(
        uptime_today,
        (seconds_since_midnight - downtime_in_hours * 60 * 60) / seconds_since_midnight,
        0.001
      )
    end
  end

  defp add_hours(datetime, hours), do: DateTime.add(datetime, hours * 60 * 60, :second)

  defp hours_ago(hours) when hours > 0 do
    DateTime.utc_now() |> DateTime.add(-hours * 60 * 60, :second) |> DateTime.truncate(:second)
  end
end
