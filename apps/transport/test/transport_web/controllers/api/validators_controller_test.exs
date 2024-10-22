defmodule TransportWeb.API.ValidatorsControllerTest do
  use TransportWeb.ConnCase, async: true
  import Mox

  setup :verify_on_exit!

  describe "/gtfs-transport" do
    test "without an Authorization header", %{conn: conn} do
      conn = conn |> get(~p"/api/validators/gtfs-transport")
      assert %{"error" => "You must set a valid Authorization header"} == json_response(conn, 401)
    end

    test "with an invalid Authorization header", %{conn: conn} do
      conn = conn |> put_req_header("authorization", "invalid") |> get(~p"/api/validators/gtfs-transport")
      assert %{"error" => "You must set a valid Authorization header"} == json_response(conn, 401)
    end

    test "with a valid Authorization header, no URL", %{conn: conn} do
      conn = conn |> put_req_header("authorization", "secret_token") |> get(~p"/api/validators/gtfs-transport")
      assert %{"error" => "You must include a GTFS URL"} == json_response(conn, 400)
    end

    test "with a valid Authorization header, invalid URL passed", %{conn: conn} do
      url = "foobar"

      Shared.Validation.Validator.Mock
      |> expect(:validate_from_url, fn ^url -> {:error, "Not a valid URL"} end)

      %{token: token} = authorized_client()

      assert %{"error" => "Not a valid URL"} ==
               conn
               |> put_req_header("authorization", token)
               |> get(~p"/api/validators/gtfs-transport?url=#{url}")
               |> json_response(400)
    end

    test "with a valid Authorization header, success response", %{conn: conn} do
      gtfs_url = "https://example.com/gtfs.zip"
      validator_response = %{"validator" => "response"}

      Shared.Validation.Validator.Mock
      |> expect(:validate_from_url, fn ^gtfs_url -> {:ok, validator_response} end)

      %{client: client, token: token} = authorized_client()

      logs =
        ExUnit.CaptureLog.capture_log(fn ->
          conn =
            conn
            |> put_req_header("authorization", token)
            |> get(~p"/api/validators/gtfs-transport?url=#{gtfs_url}")

          assert validator_response == json_response(conn, 200)
        end)

      assert logs =~ "Handling GTFS validation from #{client} for #{gtfs_url}"
    end

    @spec authorized_client() :: %{client: binary(), token: binary()}
    defp authorized_client do
      clients = Application.fetch_env!(:transport, :api_auth_clients)
      [client, token] = clients |> String.split(";") |> hd() |> String.split(":")
      %{client: client, token: token}
    end
  end
end
