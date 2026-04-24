defmodule Unlock.DynamicIRVE.IntegrationTest do
  use TransportWeb.ConnCase, async: false

  import Mox

  alias Unlock.DynamicIRVE.FeedStore

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    setup_telemetry_handler()

    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Unlock.DynamicIRVE.FeedSupervisor),
          is_pid(pid),
          do: DynamicSupervisor.terminate_child(Unlock.DynamicIRVE.FeedSupervisor, pid)

      :ets.delete_all_objects(FeedStore)
    end)
  end

  test "sync_feeds starts workers per feed and the controller aggregates their data into CSV" do
    parent = "test-agg"

    feed_a = %Unlock.Config.Item.Generic.HTTP{
      identifier: "id-a",
      slug: "source-a",
      target_url: "http://unused-a",
      ttl: 10
    }

    feed_b = %Unlock.Config.Item.Generic.HTTP{
      identifier: "id-b",
      slug: "source-b",
      target_url: "http://unused-b",
      ttl: 10
    }

    item = %Unlock.Config.Item.DynamicIRVEAggregate{identifier: parent, feeds: [feed_a, feed_b]}

    Unlock.Config.Fetcher.Mock |> stub(:fetch_config!, fn -> %{parent => item} end)

    Unlock.DynamicIRVESupervisor.sync_feeds()

    assert %{active: 2} = DynamicSupervisor.count_children(Unlock.DynamicIRVE.FeedSupervisor)

    now = DateTime.utc_now()
    FeedStore.put_feed(parent, "source-a", %{df: build_df("A"), last_updated_at: now, error: nil})
    FeedStore.put_feed(parent, "source-b", %{df: build_df("B"), last_updated_at: now, error: nil})

    body =
      proxy_conn()
      |> get("/resource/#{parent}?include_origin=1")
      |> response(200)

    df = Explorer.DataFrame.load_csv!(body, infer_schema_length: 0)
    assert Explorer.DataFrame.n_rows(df) == 2

    origins = df |> Explorer.DataFrame.pull("origin") |> Explorer.Series.to_list() |> Enum.sort()
    assert origins == ["source-a", "source-b"]

    # :external event must be emitted so the request counts in the proxy metrics
    assert_received {:telemetry_event, [:proxy, :request, :external], %{}, %{target: "proxy:test-agg"}}
  end

  defp build_df(marker) do
    fields = Transport.IRVE.DynamicIRVESchema.build_schema_fields_list()
    Explorer.DataFrame.new(for f <- fields, into: %{}, do: {f, ["#{marker}-#{f}"]})
  end

  # TODO: DRY this helper with the identical one in `unlock_controller_test.exs`
  # (and reconcile with the slightly different/buggy one in `conversion_controller_test.exs`).
  # Not so simple: proper factoring needs a shared support module + migration of both existing
  # call sites, which widens the PR scope beyond dyn-IRVE. Candidate for a test-infra cleanup PR.
  defp setup_telemetry_handler do
    events = Unlock.Telemetry.proxy_request_event_names()

    events
    |> Enum.flat_map(&:telemetry.list_handlers(&1))
    |> Enum.map(& &1.id)
    |> Enum.uniq()
    |> Enum.each(&:telemetry.detach/1)

    test_pid = self()

    :telemetry.attach_many(
      "dyn-irve-test-#{System.unique_integer()}",
      events,
      fn name, measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )
  end
end
