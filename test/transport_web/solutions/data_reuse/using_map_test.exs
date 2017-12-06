defmodule TransportWeb.Solution.DataReuse.UsingMapTest do
  @moduledoc """
  When the Transport team direct me to transport.data.gouv.fr,
  And that I'm looking for transport datasets to include in my application,
  And that I'm worried about their validity,
  I want to have an easy way to explore which data is available,
  And I want to know whether a dataset is valid or not,
  And I want to be able to download the dataset,
  so that I can quickly integrate it with my product,
  And that I can be sure that I'm not endangering my brand,
  And that I can be reassured that I'm not wasting my time.
  """

  use TransportWeb.ConnCase, async: false
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

  @tag :solution
  test "I can use the map to find and download transport data" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    # I can see a map with available datasets, and I can click on one of them
    # and see its details
    click({:css, "svg > g > path"})
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
