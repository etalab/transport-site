defmodule TransportWeb.API.CommunityResourceControllerTest do
  use TransportWeb.ConnCase, async: false
  use TransportWeb.ExternalCase

  test "GET /datasets/:dataset_id/community_resources/", %{conn: conn} do
    use_cassette "dataset/community-ressources-0" do
      conn       = get(conn, "/api/datasets/1/community_resources")
      data       = json_response(conn, 200) |> Map.get("data")
      resource   = List.first(data)

      assert response_content_type(conn, :jsonapi) =~ "application/vnd.api+json"
      assert is_list(data)
      assert Enum.any?(data)
      assert resource["id"] =~ "1"
      assert get_in(resource, ["attributes", "title"]) =~ "cadastre"
      assert get_in(resource, ["attributes", "url"]) =~ "torrents/cadastre"
      assert get_in(resource, ["links", "self"]) == "/datasets/1/community_resources/"
    end
  end
end
