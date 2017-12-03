defmodule TransportWeb.API.DatasetControllerTest do
  use TransportWeb.ConnCase
  use TransportWeb.CleanupCase, cleanup: ["celery_taskmeta", "datasets"]
  alias Transport.ReusableData

  setup do
    celery_task = ReusableData.create_dataset_validation! %{
      "result" => "{\"validations\": {\"errors\": []}}",
      "children" => "[]",
      "traceback" => "null"
    }

    dataset = ReusableData.create_dataset %{
      title: "Leningrad metro dataset",
      anomalies: [],
      coordinates: [-1.0, 1.0],
      download_uri: "link.to",
      license: "odc-odbl",
      slug: "leningrad-metro-dataset",
      celery_task_id: celery_task.task_id,
      validations: %{"errors": [], "warnings": [], "notices": []},
    }

    {:ok, dataset: dataset}
  end

  test "GET /api/datasets/", %{conn: conn} do
    conn = get(conn, "/api/datasets/")
    data = json_response(conn, 200) |> Map.get("data")

    assert response_content_type(conn, :jsonapi) =~ "application/vnd.api+json"
    assert is_list(data)
    assert Enum.any?(data)
  end

  test "GET /api/datasets/:slug", %{conn: conn, dataset: dataset} do
    conn = get(conn, "/api/datasets/#{dataset.slug}")
    data = json_response(conn, 200) |> Map.get("data")

    assert response_content_type(conn, :jsonapi) =~ "application/vnd.api+json"
    refute is_list(data)
    assert get_in(data, ["attributes", "coordinates"]) == dataset.coordinates
    assert get_in(data, ["links", "self"]) == "/datasets/#{dataset.slug}/"
  end
end
