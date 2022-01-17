defmodule Transport.TelemetryTest do
  use ExUnit.Case, async: true
  import Transport.Telemetry, only: [count_event: 3]

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    DB.Repo.delete_all(DB.Metrics)
    :ok
  end

  def stored_events, do: DB.Repo.all(DB.Metrics)

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
    events = Transport.Telemetry.proxy_request_event_names() ++ Transport.Telemetry.gbfs_request_event_names()

    events
    |> Enum.each(fn event ->
      refute is_nil(:telemetry.list_handlers(event))
    end)
  end
end
