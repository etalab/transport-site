defmodule Transport.ReusableDataTest do
  use ExUnit.Case, async: true
  use TransportWeb.DatabaseCase, cleanup: ["datasets"]
  alias Transport.ReusableData
  alias Transport.ReusableData.Dataset

  setup_all do
    %_{} = ReusableData.create_dataset %{
      title: "Leningrad metro dataset",
      download_url: "link.to",
      slug: "leningrad-metro-dataset",
      validations: []
    }

    :ok
  end

  doctest ReusableData
end
