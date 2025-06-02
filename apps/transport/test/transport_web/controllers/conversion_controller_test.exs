defmodule TransportWeb.ConversionControllerTest do
  use TransportWeb.ConnCase, async: true
  import DB.Factory
  alias TransportWeb.ConversionController
  doctest ConversionController, import: true

  setup do
    setup_telemetry_handler()
    # See https://elixirforum.com/t/dbconnection-ownershiperror-cannot-find-ownership-process-for-pid-0-xxx-0/41373/3
    # and https://github.com/etalab/transport-site/issues/3434
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(DB.Repo)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  end

  describe "get" do
    test "when the resource does not exist", %{conn: conn} do
      assert conn |> get(conversion_path(conn, :get, 42, "GeoJSON")) |> text_response(404) == "Conversion not found."
    end

    test "when the conversion format does not exist", %{conn: conn} do
      assert conn |> get(conversion_path(conn, :get, 42, "foo")) |> text_response(404) ==
               "Conversion not found. `convert_to` is not a possible value."
    end

    test "when the resource exists but there are no conversions", %{conn: conn} do
      resource = insert(:resource)

      assert conn |> get(conversion_path(conn, :get, resource.id, "GeoJSON")) |> text_response(404) ==
               "Conversion not found."
    end

    test "with an existing conversion", %{conn: conn} do
      resource = insert(:resource, format: "GTFS")

      insert(:resource_history,
        resource_id: resource.id,
        payload: %{"uuid" => uuid1 = Ecto.UUID.generate()},
        last_up_to_date_at: last_up_to_date_at = DateTime.utc_now()
      )

      insert(:data_conversion,
        resource_history_uuid: uuid1,
        convert_from: "GTFS",
        convert_to: "GeoJSON",
        converter: DB.DataConversion.converter_to_use("GeoJSON"),
        payload: %{"permanent_url" => permanent_url = "https://example.com/url1", "filesize" => 42}
      )

      # Relevant headers are sent and we return a redirect response
      conn_redirected = conn |> get(conversion_path(conn, :get, resource.id, "GeoJSON"))

      assert [
               {"cache-control", "public, max-age=300"},
               {"etag", ConversionController.md5_hash(permanent_url)},
               {"x-last-up-to-date-at", last_up_to_date_at |> DateTime.to_iso8601()},
               {"x-robots-tag", "noindex"}
             ] ==
               conn_redirected.resp_headers
               |> Enum.filter(fn {k, _} -> k in ["cache-control", "etag", "x-last-up-to-date-at", "x-robots-tag"] end)
               |> Enum.sort_by(fn {k, _} -> k end, :asc)

      assert redirected_to(conn_redirected, 302) == permanent_url

      # A request is recorded in the `metrics` table, with a `period` at the day level
      target = "resource_id:#{resource.id}"
      period = %{DateTime.truncate(DateTime.utc_now(), :second) | second: 0, minute: 0, hour: 0}
      assert_received {:telemetry_event, [:conversions, :get, :GeoJSON], %{}, %{target: ^target}}

      # Need to wait a few milliseconds because the real telemetry handler
      # writes rows in the database asynchronously.
      # NOTE: to be improved in the future
      Process.sleep(100)

      assert [%DB.Metrics{target: ^target, event: "conversions:get:GeoJSON", period: ^period, count: 1}] =
               DB.Metrics |> DB.Repo.all()
    end
  end

  defp setup_telemetry_handler do
    # inspired by https://github.com/dashbitco/broadway/blob/main/test/broadway_test.exs
    :telemetry.attach_many(
      "test-handler-#{System.unique_integer()}",
      Transport.Telemetry.conversions_get_event_names(),
      fn name, measurements, metadata, _ ->
        send(self(), {:telemetry_event, name, measurements, metadata})
      end,
      nil
    )
  end
end
