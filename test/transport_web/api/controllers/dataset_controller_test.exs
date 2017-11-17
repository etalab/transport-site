defmodule TransportWeb.API.DatasetControllerTest do
  use TransportWeb.ConnCase
  alias Transport.ReusableData

  setup do
    dataset = ReusableData.create_dataset %{
      title: "Leningrad metro dataset",
      anomalies: [],
      coordinates: [-1.0, 1.0],
      download_uri: "link.to",
      license: "odc-odbl",
      slug: "leningrad-metro-dataset"
    }

    {:ok, dataset: dataset}
  end

  test "GET /api/datasets/", %{conn: conn, dataset: dataset} do
    conn = get(conn, "/api/datasets/")
    data = json_response(conn, 200) |> Map.get("data") |> List.first()

    assert response_content_type(conn, :jsonapi) =~ "application/vnd.api+json"
    assert get_in(data, ["attributes", "coordinates"]) == dataset.coordinates
    assert get_in(data, ["links", "self"]) == "/datasets/#{dataset.slug}/"
  end
end
