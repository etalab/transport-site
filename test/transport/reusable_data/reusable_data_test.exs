defmodule Transport.ReusableDataTest do
  use ExUnit.Case, async: true
  use TransportWeb.DatabaseCase, cleanup: ["celery_taskmeta", "datasets"]
  alias Transport.ReusableData
  alias Transport.ReusableData.Dataset

  setup_all do
    %_{} = ReusableData.create_dataset %{
      title: "Leningrad metro dataset",
      anomalies: [],
      coordinates: [-0.5630548425091684,47.47654241641714],
      download_uri: "link.to",
      slug: "leningrad-metro-dataset",
      validations: %{"errors" => [], "warnings" => [], "notices" => []}
    }

    :ok
  end

  doctest ReusableData
end
