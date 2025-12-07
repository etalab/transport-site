defmodule Transport.TelemetryTest do
  use ExUnit.Case, async: true
  import Transport.Telemetry, only: [count_event: 3, count_event: 4]
  import Mox

  setup :verify_on_exit!

  doctest Transport.Telemetry, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def stored_events, do: DB.Repo.all(DB.Metrics)

  test "telemetry for incr_event" do
    assert DB.Repo.all(DB.Metrics) |> Enum.empty?()
    assert %{} == :sys.get_state(Unlock.BatchMetrics)

    Unlock.BatchMetrics.Mock
    |> expect(:incr_event, fn %{target: "foo", event: "proxy:request:external"} ->
      :ok
    end)

    # Dispatch the Telemetry event
    :telemetry.execute(
      [:proxy, :request, :external],
      %{},
      %{target: "foo"}
    )

    assert DB.Repo.all(DB.Metrics) |> Enum.empty?()
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
