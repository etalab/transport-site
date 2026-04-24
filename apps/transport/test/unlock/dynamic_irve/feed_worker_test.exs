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
    expect(Transport.Req.Mock, :get!, fn _url, _opts ->
      %Req.Response{status: 200, body: csv_fixture()}
    end)

    {:ok, pid} = FeedWorker.start_link({"parent", feed("ok")})
    send(pid, :tick)
    :sys.get_state(pid)

    stored = FeedStore.get_feed("parent", "ok")
    assert %{error: nil, last_updated_at: %DateTime{}, df: %Explorer.DataFrame{} = df} = stored
    assert Explorer.DataFrame.n_rows(df) == 1
  end

  test "HTTP 500 → error recorded, worker still alive" do
    expect(Transport.Req.Mock, :get!, fn _url, _opts ->
      %Req.Response{status: 500, body: "oops"}
    end)

    {:ok, pid} = FeedWorker.start_link({"parent", feed("ko")})
    send(pid, :tick)
    :sys.get_state(pid)

    assert %{error: "HTTP 500", last_errored_at: %DateTime{}} = FeedStore.get_feed("parent", "ko")
    assert Process.alive?(pid)
  end

  defp feed(slug) do
    %Unlock.Config.Item.Generic.HTTP{
      identifier: "id-#{slug}",
      slug: slug,
      target_url: "http://example.test/feed",
      ttl: 10
    }
  end

  defp csv_fixture do
    headers = Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
    row = Enum.map(headers, fn h -> "val-#{h}" end)
    Enum.join([Enum.join(headers, ","), Enum.join(row, ",")], "\n")
  end
end
