defmodule Unlock.DynamicIRVE.FeedWorkerTest do
  use ExUnit.Case, async: false

  import Mox

  alias Unlock.DynamicIRVE.{FeedStore, FeedWorker}

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    on_exit(fn -> :ets.delete_all_objects(FeedStore) end)
  end

  test "HTTP 200 + valid CSV → DataFrame stored, no error" do
    feed = feed("slug-001")
    # Forward the URL to the test process: the worker rescues exceptions
    # (including ExUnit assertions), so we assert outside the Mox callback.
    test_pid = self()

    expect(Transport.Req.Mock, :get!, fn url, _opts ->
      send(test_pid, {:fetched, url})
      %Req.Response{status: 200, body: csv_fixture()}
    end)

    {:ok, pid} = FeedWorker.start_link({"parent", feed})
    send(pid, :tick)
    await_genserver_messages_processed(pid)

    assert_received {:fetched, url}
    assert url == feed.target_url

    stored = FeedStore.get_feed("parent", "slug-001")
    assert %{error: nil, last_updated_at: %DateTime{}, df: %Explorer.DataFrame{} = df} = stored
    assert Explorer.DataFrame.n_rows(df) == 1
  end

  test "HTTP 500 → error recorded, worker still alive" do
    feed = feed("slug-002")
    test_pid = self()

    expect(Transport.Req.Mock, :get!, fn url, _opts ->
      send(test_pid, {:fetched, url})
      %Req.Response{status: 500, body: "oops"}
    end)

    {:ok, pid} = FeedWorker.start_link({"parent", feed})
    send(pid, :tick)
    await_genserver_messages_processed(pid)

    assert_received {:fetched, url}
    assert url == feed.target_url

    assert %{error: "HTTP 500", last_errored_at: %DateTime{}} = FeedStore.get_feed("parent", "slug-002")
    assert Process.alive?(pid)
  end

  # Sync barrier: a GenServer handles one message at a time, in FIFO order from
  # any given sender. `:sys.get_state/1` is itself a message — it only returns
  # once every message we sent earlier from this process has been fully handled.
  # The returned state is discarded.
  defp await_genserver_messages_processed(pid), do: :sys.get_state(pid)

  defp feed(slug) do
    %Unlock.Config.Item.Generic.HTTP{
      identifier: "id-#{slug}",
      slug: slug,
      target_url: "http://example.test/feed/#{slug}",
      ttl: 10
    }
  end

  defp csv_fixture do
    headers = Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
    row = Enum.map(headers, fn h -> "val-#{h}" end)
    Enum.join([Enum.join(headers, ","), Enum.join(row, ",")], "\n")
  end
end
