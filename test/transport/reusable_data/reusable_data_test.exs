defmodule Transport.ReusableDataTest do
  use ExUnit.Case, async: true
  use TransportWeb.CleanupCase, cleanup: ["celery_taskmeta", "datasets"]
  alias Transport.ReusableData
  alias Transport.ReusableData.Dataset

  setup_all do
    celery_task = ReusableData.create_dataset_validation! %{
      "result" => "{\"validations\": {\"errors\": []}}",
      "children" => "[]",
      "traceback" => "null"
    }

    ReusableData.create_dataset %{
      title: "Leningrad metro dataset",
      anomalies: [],
      coordinates: [-1.0, 1.0],
      download_uri: "link.to",
      slug: "leningrad-metro-dataset",
      celery_task_id: celery_task.task_id
    }

    :ok
  end

  doctest ReusableData
end
