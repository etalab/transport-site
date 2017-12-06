defmodule TransportWeb.Solution.DataReuse.UsingListTest do
  @moduledoc """
  When the Transport team direct me to transport.data.gouv.fr,
  And that I'm looking for transport datasets to include in my application,
  And that I'm worried about their validity,
  I want to have an easy way to list available datasets,
  And I want to know whether a dataset is valid or not,
  And I want to be able to download the dataset,
  so that I can quickly integrate it with my product,
  And that I can be sure that I'm not endangering my brand,
  And that I can be reassured that I'm not wasting my time.
  """

  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: ["celery_taskmeta", "datasets"]
  use TransportWeb.UserFacingCase
  alias Transport.ReusableData

  setup_all do
    %_{} = ReusableData.create_dataset %{
      download_uri: "https://link.to/angers.zip",
      license: "odc-odbl",
      title: "Angers GTFS",
      anomalies: [],
      coordinates: [-0.5630548425091684,47.47654241641714],
      slug: "angers-gtfs",
      validations: %{"errors" => [], "warnings" => [], "notices" => []}
    }

    :ok
  end

  @tag :integration
  test "I can list available datasets to find and download transport data" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    # I can click to the a list of available datasets
    click({:link_text, "Réutiliser des données"})

    # I can see or read somewhere that the datasets are valid
    assert visible_page_text() =~ "Jeux de données valides disponibles"

    # I can click on a dataset and see its details
    click({:link_text, "Angers GTFS"})
    assert visible_page_text() =~ "Angers GTFS"

    # I can see or read somewhere that the dataset is valid
    assert visible_page_text() =~ "Valide"

    # I can download the dataset
    find_element(:class, "shortlist__link--download")
    |> find_within_element(:link_text, "Télécharger")
    |> attribute_value("href")
    |> Kernel.=~("zip")
    |> assert
  end
end
