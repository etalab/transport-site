defmodule TransportWeb.ConversionControllerTest do
  use TransportWeb.ConnCase, async: true

  setup do
    setup_telemetry_handler()
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "get" do
    test "when the resource does not exist", %{conn: conn} do
      assert conn |> get(conversion_path(conn, :get, 42, "NeTEx")) |> text_response(404) == "Conversion not found."
    end

    test "when the conversion format does not exist", %{conn: conn} do
      assert conn |> get(conversion_path(conn, :get, 42, "foo")) |> text_response(404) ==
               "Conversion not found. `convert_to` is not a possible value."
    end
  end

  defp setup_telemetry_handler do
    events = Transport.Telemetry.conversions_get_event_names()
    events |> Enum.at(1) |> :telemetry.list_handlers() |> Enum.map(& &1.id) |> Enum.each(&:telemetry.detach/1)
    test_pid = self()
    # inspired by https://github.com/dashbitco/broadway/blob/main/test/broadway_test.exs
    :telemetry.attach_many(
      "test-handler-#{System.unique_integer()}",
      events,
      fn name, measurements, metadata, _ ->
        send(test_pid, {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )
  end
end
