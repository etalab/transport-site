defmodule Transport.HistoryTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  import TransportWeb.Factory
  import Ecto.Query
  import Mox

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "backup_resources" do
    logs =
      capture_log(fn ->
        resource =
          insert(:resource,
            url: "http://localhost",
            title: "Hello",
            format: "GTFS",
            is_community_resource: false,
            dataset: insert(:dataset)
          )

        assert :ok == Transport.History.Backup.backup_resources()
      end)

    assert logs == []
  end

  test "history_resources" do
    dataset = insert(:dataset)

    Transport.History.Fetcher.history_resources(dataset)
  end
end
