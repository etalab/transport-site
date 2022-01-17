defmodule Datagouvfr.Client.ReusesTest do
  use ExUnit.Case, async: true
  alias Datagouvfr.Client.API
  alias Datagouvfr.Client.Reuses
  import Datagouvfr.ApiFixtures, only: [mock_httpoison_request: 3]
  import Mox

  setup :verify_on_exit!

  describe "get" do
    test "with a 200" do
      mock_httpoison_request(
        "reuses" |> API.process_url(),
        {:ok, %HTTPoison.Response{status_code: 200, body: ~s({"data":[], "owner": null})}},
        follow_redirect: true,
        params: %{dataset: "id"}
      )

      assert {:ok, []} == Reuses.get(%{datagouv_id: "id"})
    end

    test "with a server error" do
      mock_httpoison_request(
        "reuses" |> API.process_url(),
        {:ok, %HTTPoison.Response{status_code: 500, body: ~s({"message": "Internal Server Error"})}},
        follow_redirect: true,
        params: %{dataset: "id"}
      )

      assert {:error, ~s(Unable to get reuses of dataset id because of %{"message" => "Internal Server Error"})} ==
               Reuses.get(%{datagouv_id: "id"})
    end

    test "with a decode error" do
      mock_httpoison_request(
        "reuses" |> API.process_url(),
        {:ok, %HTTPoison.Response{status_code: 200, body: "foo"}},
        follow_redirect: true,
        params: %{dataset: "id"}
      )

      {:error, message} = Reuses.get(%{datagouv_id: "id"})
      assert String.starts_with?(message, "Unable to get reuses of dataset id because of %Jason.DecodeError")
    end
  end
end
