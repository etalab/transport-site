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

  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  use TransportWeb.ConnCase, async: false
  use TransportWeb.UserFacingCase
  alias Transport.{Dataset, Repo, Resource, Validation}

  setup do
    {:ok, _} = %Dataset{
      description: "Un jeu de données",
      licence: "odc-odbl",
      title: "Horaires et arrêts du réseau IRIGO - format GTFS",
      slug: "horaires-et-arrets-du-reseau-irigo-format-gtfs",
      datagouv_id: "5b4cd3a0b59508054dd496cd",
      frequency: "yearly",
      tags: [],
      resources: [%Resource{
        url: "https://link.to/angers.zip",
        validation: %Validation{},
        metadata: %{}
      }
    ]
    } |> Repo.insert()

    {:ok, _} = %Dataset{
      description: "Un autre jeu de données",
      licence: "odc-odbl",
      title: "offre de transport du réseau de LAVAL Agglomération (GTFS)",
      slug: "offre-de-transport-du-reseau-de-laval-agglomeration-gtfs",
      datagouv_id: "5bc493d08b4c416c84a69500",
      frequency: "yearly",
      tags: [],
      resources: [%Resource{
        url: "https://link.to/angers.zip",
        validation: %Validation{},
        metadata: %{}
      }]
    } |> Repo.insert()

    :ok
  end

  @tag :integration
  test "I can list available datasets to find and download transport data" do
    @endpoint
    |> page_url(:index)
    |> navigate_to

    # I can click to the a list of available datasets
    click({:link_text, "Voir les derniers jeux de données ajoutés"})

    # I can see or read somewhere that the datasets are valid
    assert visible_page_text() =~ "Jeux de données valides disponibles"
    # I can click on a dataset and see its details
    click({:link_text, "Horaires et arrêts du réseau IRIGO - format GTFS"})
    assert visible_page_text() =~ "IRIGO"

    # I can download the dataset
    :class
    |> find_element("shortlist__link--download")
    |> find_within_element(:link_text, "Télécharger")
    |> attribute_value("href")
    |> Kernel.=~("zip")
    |> assert
  end
end
