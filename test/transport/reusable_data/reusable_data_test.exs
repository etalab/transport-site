defmodule Transport.ReusableDataTest do
  use ExUnit.Case, async: true
  use TransportWeb.CleanupCase, cleanup: ["datasets"]
  alias Transport.ReusableData
  alias Transport.ReusableData.Dataset

  setup_all do
    ReusableData.create_dataset %{
      title: "Leningrad metro dataset",
      anomalies: [],
      coordinates: [-1.0, 1.0],
      download_uri: "link.to",
      slug: "leningrad-metro-dataset"
    }

    :ok
  end

  doctest ReusableData
end
