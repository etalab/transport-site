defmodule Transport.ResourceQualityLoggerTest do
  @moduledoc """
  A test module for Transport.ResourceQualityLogger.
  """
  use ExUnit.Case
  import TransportWeb.Factory
  alias DB.{LogsResourceQuality, Resource}
  alias Transport.ResourceQualityLogger
  doctest Transport.ResourceQualityLogger

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "log resources quality metrics" do
    resource1 = insert(:resource, %{is_available: true, end_date: %Date{year: 2021, month: 8, day: 23}})
    resource2 = insert(:resource, %{is_available: false, end_date: %Date{year: 2020, month: 8, day: 23}})

    assert Resource |> DB.Repo.all() |> length == 2

    ResourceQualityLogger.insert_all_resources_logs()

    logs = LogsResourceQuality |> DB.Repo.all()

    assert logs |> length == 2

    resource1_log = logs |> Enum.find(&(&1.resource_id == resource1.id))
    assert resource1_log |> Map.fetch!(:resource_end_date) == resource1.end_date
    assert resource1_log |> Map.fetch!(:is_available) == resource1.is_available

    resource2_log = logs |> Enum.find(&(&1.resource_id == resource2.id))
    assert resource2_log |> Map.fetch!(:resource_end_date) == resource2.end_date
    assert resource2_log |> Map.fetch!(:is_available) == resource2.is_available
  end
end
