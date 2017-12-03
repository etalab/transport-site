defmodule TransportWeb.ReuseDataTest do
  @moduledoc """
  When the Transport team direct me to transport.data.gouv.fr
  I want to have an easy way to explore which data is available,
  and be able to download it,
  so I can quickly integrate to my product(s).
  """

  use TransportWeb.ConnCase, async: true
  use TransportWeb.CleanupCase, cleanup: ["celery_taskmeta", "datasets"]
  use Hound.Helpers
  alias Transport.ReusableData

  hound_session()

  setup_all do
    celery_task = ReusableData.create_dataset_validation! %{
      "result" => "{\"validations\": {\"errors\": []}}",
      "children" => "[]",
      "traceback" => "null"
    }

    ReusableData.create_dataset %{
      download_uri: "https://link.to/angers.zip",
      license: "odc-odbl",
      title: "Angers GTFS",
      anomalies: [],
      coordinates: [1.0, 1.0],
      slug: "angers-gtfs",
      celery_task_id: celery_task.task_id,
      validations: %{"errors" => [], "warnings" => [], "notices" => []},
    }

    :ok
  end

  @tag :integration
  test "I can click on the map to reuse transport data" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    click({:css, "svg > g > path"})

    find_element(:class, "map__link")
    |> attribute_value("href")
    |> Kernel.=~("/datasets/angers-gtfs")
    |> assert
  end

  @tag :integration
  test "I can click on a button to see available datasets" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    click({:class, "hero__link--reuse"})

    assert visible_page_text() =~ "Jeux de données disponibles"

    find_element(:class, "shortlist")
    |> find_within_element(:class, "shortlist-description")
    |> find_within_element(:tag, "h2")
    |> inner_text
    |> Kernel.=~("Angers GTFS")
    |> assert
  end

  @tag :integration
  test "I can download a dataset from the list of available datasets" do
    @endpoint
    |> dataset_url(:index)
    |> navigate_to

    find_element(:class, "shortlist__link--download")
    |> find_within_element(:link_text, "Télécharger")
    |> attribute_value("href")
    |> Kernel.=~("zip")
    |> assert
  end
end
