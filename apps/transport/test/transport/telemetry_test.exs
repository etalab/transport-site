defmodule Transport.TelemetryTest do
  use ExUnit.Case, async: true
  import Transport.Telemetry, only: [incr_event: 2, count_event: 3, count_event: 4]
  import Unlock.Shared
  doctest Transport.Telemetry, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    DB.Repo.delete_all(DB.Metrics)
    Cachex.clear(cache_name())
    on_exit(fn -> Cachex.clear(cache_name()) end)
    :ok
  end

  def stored_events, do: DB.Repo.all(DB.Metrics)

  test "incr_event" do
    assert [] == metric_cache_keys()
    assert nil == cache_entry(metric_cache_key(%{target: target = "foo", event: type = "external"}))

    incr_event(target, type)

    assert 1 == cache_entry(metric_cache_key(%{target: target, event: type}))
    assert [metric_cache_key(%{target: target, event: type})] == metric_cache_keys()
  end

  test "telemetry for incr_event" do
    assert [] == metric_cache_keys()

    # Dispatch the Telemetry event
    :telemetry.execute(
      [:proxy, :request, :external],
      %{},
      %{target: "foo"}
    )

    # Wait a bit for the async task
    :timer.sleep(100)

    [cache_key] = metric_cache_keys()
    assert "metric@@proxy:request:external@foo" == cache_key

    assert 1 == cache_entry(cache_key)
    {:ok, ttl} = cache_ttl(cache_key)
    assert_in_delta :timer.seconds(60), ttl, 1_000
    assert [cache_key] == metric_cache_keys()
  end

  test "aggregates same hour for a given identifier/event" do
    count_event("id-001", [:proxy, :request, :internal], ~U[2021-11-22 14:28:06.098765Z])
    count_event("id-001", [:proxy, :request, :internal], ~U[2021-11-22 14:28:56.098765Z])

    assert [
             %{
               count: 2,
               event: "proxy:request:internal",
               period: ~U[2021-11-22 14:00:00Z],
               target: "id-001"
             }
           ] = stored_events()
  end

  test "count_event can aggregate at the day level" do
    count_event("id-001", [:proxy, :request, :internal], ~U[2021-11-22 14:28:06.098765Z], :day)
    count_event("id-001", [:proxy, :request, :internal], ~U[2021-11-23 15:29:56.098765Z], :day)

    assert [
             %{
               count: 1,
               event: "proxy:request:internal",
               period: ~U[2021-11-22 00:00:00Z],
               target: "id-001"
             },
             %{
               count: 1,
               event: "proxy:request:internal",
               period: ~U[2021-11-23 00:00:00Z],
               target: "id-001"
             }
           ] = stored_events()
  end

  test "dissociates events at different hours" do
    count_event("id-001", [:proxy, :request, :internal], ~U[2021-11-22 14:28:06.098765Z])
    count_event("id-001", [:proxy, :request, :internal], ~U[2021-11-22 15:29:56.098765Z])

    assert [
             %{
               count: 1,
               event: "proxy:request:internal",
               period: ~U[2021-11-22 14:00:00Z],
               target: "id-001"
             },
             %{
               count: 1,
               event: "proxy:request:internal",
               period: ~U[2021-11-22 15:00:00Z],
               target: "id-001"
             }
           ] = stored_events()
  end

  test "dissociates events for different events and identifiers at the same hour" do
    count_event(id = "id-001", event = [:first_event], datetime = ~U[2021-11-22 14:28:06.098765Z])
    count_event(id, second_event = [:second_event], datetime)
    count_event("id-002", event, datetime)
    count_event("id-003", second_event, datetime)

    assert stored_events() |> Enum.count() == 4
  end

  test "handlers have been registered" do
    Transport.Telemetry.proxy_request_event_names()
    |> Kernel.++(Transport.Telemetry.conversions_get_event_names())
    |> Enum.each(fn event -> refute is_nil(:telemetry.list_handlers(event)) end)
  end
end
