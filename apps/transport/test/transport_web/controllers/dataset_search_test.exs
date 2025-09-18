defmodule TransportWeb.DatasetSearchControllerTest do
  use TransportWeb.ConnCase, async: true
  use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory

  doctest TransportWeb.DatasetController

  setup do
    insert(:dataset,
      created_at: DateTime.utc_now(),
      last_update: DateTime.utc_now(),
      description: "Un jeu de données",
      licence: "odc-odbl",
      datagouv_title: "Horaires et arrêts du réseau IRIGO - format GTFS",
      custom_title: "Horaires Angers",
      type: "public-transit",
      slug: "horaires-et-arrets-du-reseau-irigo-format-gtfs",
      datagouv_id: "5b4cd3a0b59508054dd496cd",
      frequency: "yearly",
      tags: [],
      resources: [
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "https://link.to/angers.zip",
          title: "angers.zip"
        }
      ],
      aom: %DB.AOM{id: 4242, nom: "Angers Métropôle"}
    )

    insert(:dataset,
      created_at: DateTime.utc_now(),
      last_update: DateTime.utc_now(),
      description: "Un autre jeu de données",
      licence: "lov2",
      datagouv_title: "offre de transport du réseau de LAVAL Agglomération (GTFS)",
      custom_title: "Horaires Laval",
      slug: "offre-de-transport-du-reseau-de-laval-agglomeration-gtfs",
      type: "public-transit",
      datagouv_id: "5bc493d08b4c416c84a69500",
      frequency: "yearly",
      tags: [],
      resources: [
        %DB.Resource{
          last_update: DateTime.utc_now() |> DateTime.add(-6, :hour),
          last_import: DateTime.utc_now() |> DateTime.add(-1, :hour),
          url: "https://link.to/angers.zip"
        }
      ]
    )

    :ok
  end

  test "GET /datasets title", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    # titre de la page
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "GET /datasets filter", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index))
    # info dans les filtres à gauche des datasets
    assert html_response(conn, 200) =~ "Transport public collectif (2)"
  end

  describe "list datasets" do
    test "with modes" do
      %DB.Resource{dataset_id: dataset_1_id} =
        insert(:resource, counter_cache: %{gtfs_modes: ["rollerblades"]}, dataset: insert(:dataset))

      %DB.Resource{dataset_id: dataset_2_id} =
        insert(:resource, counter_cache: %{gtfs_modes: ["rollerblades", "tramway"]}, dataset: insert(:dataset))

      %DB.Resource{} =
        insert(:resource, counter_cache: %{gtfs_modes: ["bus"]}, dataset: insert(:dataset))

      %DB.Resource{} = insert(:resource, counter_cache: %{gtfs_modes: []}, dataset: insert(:dataset))
      %DB.Resource{} = insert(:resource, counter_cache: nil, dataset: insert(:dataset))

      datasets = %{"modes" => ["rollerblades"]} |> DB.Dataset.list_datasets() |> DB.Repo.all()
      assert datasets |> Enum.map(& &1.id) |> Enum.sort() == [dataset_1_id, dataset_2_id]

      # Doesn’t crash if we mix the search with other filters
      assert [] == %{"modes" => ["bus"], "features" => ["realtime"]} |> DB.Dataset.list_datasets() |> DB.Repo.all()

      # Doesn’t crash and sends back the whole list if we search for nil
      refute Enum.empty?(%{"modes" => nil} |> DB.Dataset.list_datasets() |> DB.Repo.all())
    end

    test "with features" do
      %DB.Resource{dataset_id: dataset_1_id} =
        insert(:resource, counter_cache: %{gtfs_features: ["repose pieds en velour"]}, dataset: insert(:dataset))

      %DB.Resource{dataset_id: dataset_2_id} =
        insert(:resource,
          counter_cache: %{gtfs_features: ["repose pieds en velour", "DJ à bord"]},
          dataset: insert(:dataset)
        )

      datasets = %{"features" => ["repose pieds en velour"]} |> DB.Dataset.list_datasets() |> DB.Repo.all()
      assert datasets |> Enum.map(& &1.id) |> Enum.sort() == [dataset_1_id, dataset_2_id]

      [dataset] = %{"features" => ["DJ à bord"]} |> DB.Dataset.list_datasets() |> DB.Repo.all()
      assert dataset.id == dataset_2_id
    end

    test "with gtfs-rt features" do
      %{id: region_id} = insert(:region)
      %{id: dataset_id} = insert(:dataset, type: "public-transit", region_id: region_id)
      %{id: resource_id} = insert(:resource, dataset_id: dataset_id)
      insert(:resource_metadata, resource_id: resource_id, features: ["vehicle_positions"])

      # insert a second matching resource, to check "distinct" on dataset_id works (no duplicate result)
      %{id: resource_id_again} = insert(:resource, dataset_id: dataset_id)
      insert(:resource_metadata, resource_id: resource_id_again, features: ["vehicle_positions"])

      %{id: dataset_id_2} = insert(:dataset, type: "public-transit", region_id: region_id)
      %{id: resource_id_2} = insert(:resource, dataset_id: dataset_id_2)

      # feature has been seen, but too long ago
      insert(:resource_metadata,
        resource_id: resource_id_2,
        features: ["vehicle_positions"],
        inserted_at: ~U[2020-01-01 00:00:00Z]
      )

      %{id: dataset_id_3} = insert(:dataset, type: "public-transit", region_id: region_id)
      %{id: resource_id_3} = insert(:resource, dataset_id: dataset_id_3)
      insert(:resource_metadata, resource_id: resource_id_3, features: ["repose pieds en velour"])

      assert [%{id: ^dataset_id}] =
               %{"features" => ["vehicle_positions"]}
               |> TransportWeb.DatasetController.get_datasets()
               |> Map.fetch!(:entries)

      assert [%{count: 1, type: "public-transit"}] =
               %{"features" => ["vehicle_positions"]} |> TransportWeb.DatasetController.get_types()

      regions_count = %{"features" => ["vehicle_positions"]} |> TransportWeb.DatasetController.get_regions()
      assert [%{count: 1, id: ^region_id}] = regions_count |> Enum.filter(&(&1.id == region_id))
    end
  end

  test "GET /datasets?type=public-transit", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{type: "public-transit"})
    assert html_response(conn, 200) =~ "Jeux de données"
  end

  test "GET /datasets?type=public-transit&licence=odc-odbl", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :index), %{type: "public-transit", licence: "odc-odbl"})
    assert html_response(conn, 200) =~ "Transport public collectif (1)"
    assert html_response(conn, 200) =~ "Horaires Angers"
    refute html_response(conn, 200) =~ "Horaires Laval"

    conn = conn |> get(dataset_path(conn, :index), %{type: "public-transit", licence: "licence-ouverte"})
    assert html_response(conn, 200) =~ "Horaires Laval"
    refute html_response(conn, 200) =~ "Horaires Angers"
  end

  test "searching with a custom tag" do
    %DB.Dataset{id: dataset_id} =
      insert(:dataset, type: "public-transit", is_active: true, custom_tags: ["bar", "foo"])

    assert 3 == %{"type" => "public-transit"} |> Dataset.list_datasets() |> Repo.all() |> Enum.count()

    assert [%DB.Dataset{id: ^dataset_id}] =
             %{"type" => "public-transit", "custom_tag" => "foo"} |> Dataset.list_datasets() |> Repo.all()

    assert 1 == DB.Dataset.count_by_custom_tag("foo")
  end

  test "searching by resource format" do
    %DB.Dataset{id: d1_id} = insert(:dataset)
    insert(:resource, dataset_id: d1_id, format: "GTFS")
    insert(:resource, dataset_id: d1_id, format: "gtfs-rt")

    %DB.Dataset{id: d2_id} = insert(:dataset)
    insert(:resource, dataset_id: d2_id, format: "gbfs")

    %DB.Dataset{id: d3_id} = insert(:dataset)
    insert(:resource, dataset_id: d3_id, format: "csv")
    insert(:resource, dataset_id: d3_id, format: "csv")

    assert [%DB.Dataset{id: ^d1_id}] = %{"format" => "GTFS"} |> DB.Dataset.list_datasets() |> DB.Repo.all()
    assert [%DB.Dataset{id: ^d2_id}] = %{"format" => "gbfs"} |> DB.Dataset.list_datasets() |> DB.Repo.all()
    assert [%DB.Dataset{id: ^d3_id}] = %{"format" => "csv"} |> DB.Dataset.list_datasets() |> DB.Repo.all()
    assert [] = %{"format" => "NeTEx"} |> DB.Dataset.list_datasets() |> DB.Repo.all()
  end

  test "search for datasets published by an organization" do
    %DB.Organization{id: org_id} = insert(:organization)
    %Dataset{id: dataset_id} = insert(:dataset, organization_id: org_id, is_active: true)
    # other dataset by another org, shouldn’t be found
    %DB.Organization{id: other_org_id} = insert(:organization)
    %Dataset{id: _other_dataset_id} = insert(:dataset, organization_id: other_org_id, is_active: true)

    assert [%Dataset{id: ^dataset_id}] =
             %{"organization_id" => to_string(org_id)} |> Dataset.list_datasets() |> Repo.all()
  end

  test "a dataset labelled as base nationale published by us is first without filters" do
    %{id: base_nationale_dataset_id} =
      insert(:dataset,
        type: "public-transit",
        custom_title: "Base nationale des GTFS",
        organization_id: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_id)
      )

    results = %{"type" => "public-transit"} |> Dataset.list_datasets() |> Repo.all()
    assert Enum.count(results) == 3
    assert %Dataset{id: ^base_nationale_dataset_id} = hd(results)

    %{id: first_dataset_id} =
      %{"type" => "public-transit", "q" => "angers"} |> Dataset.list_datasets() |> Repo.all() |> hd()

    assert first_dataset_id != base_nationale_dataset_id
  end

  test "uses population and custom_title to sort by default" do
    small_aom = insert(:aom, population: 100)
    big_aom = insert(:aom, population: 200)
    type = "private-parking"

    # small population: last result expected
    small_dataset = insert(:dataset, is_active: true, type: type, aom: small_aom, custom_title: "AAA")
    # equal population, alphabetical order expected
    big_dataset_1 = insert(:dataset, is_active: true, type: type, aom: big_aom, custom_title: "ABC")
    big_dataset_2 = insert(:dataset, is_active: true, type: type, aom: big_aom, custom_title: "BBB")
    # national dataset, population is null
    national_dataset = insert(:dataset, is_active: true, type: type, population: nil)

    assert [national_dataset.id, big_dataset_1.id, big_dataset_2.id, small_dataset.id] ==
             %{"type" => type} |> Dataset.list_datasets() |> DB.Repo.all() |> Enum.map(& &1.id)
  end

  test "hidden datasets are not included" do
    hidden_dataset = insert(:dataset, is_active: true, is_hidden: true)

    refute hidden_dataset.id in (%{} |> DB.Dataset.list_datasets() |> DB.Repo.all() |> Enum.map(& &1.id))
  end

  test "sort by most_recent" do
    today = DateTime.utc_now()
    last_week = DateTime.add(today, -7, :day)
    type = "private-parking"

    older_dataset = insert(:dataset, type: type, inserted_at: last_week)
    recent_dataset = insert(:dataset, type: type, inserted_at: today)
    null_dataset = insert(:dataset, type: type) |> Ecto.Changeset.change(%{inserted_at: nil}) |> DB.Repo.update!()

    assert [recent_dataset.id, older_dataset.id, null_dataset.id] ==
             %{"type" => type, "order_by" => "most_recent"}
             |> Dataset.list_datasets()
             |> DB.Repo.all()
             |> Enum.map(& &1.id)
  end

  test "sort by alpha" do
    type = "private-parking"

    b_dataset = insert(:dataset, type: type, custom_title: "B")
    a_dataset = insert(:dataset, type: type, custom_title: "A")

    assert [a_dataset.id, b_dataset.id] ==
             %{"type" => type, "order_by" => "alpha"} |> Dataset.list_datasets() |> DB.Repo.all() |> Enum.map(& &1.id)
  end

  test "search by department" do
    departement = insert(:departement)
    commune = insert(:commune, insee: "1", departement_insee: departement.insee)
    epci = insert(:epci, insee: "2")
    insert(:commune, insee: "3", departement_insee: departement.insee, epci_insee: epci.insee)
    region = insert(:region, insee: "4")
    insert(:commune, insee: "5", departement_insee: departement.insee, region_id: region.id)

    departement_ad =
      insert(:administrative_division,
        type: :departement,
        type_insee: "departement_#{departement.insee}",
        insee: departement.insee
      )

    commune_ad =
      insert(:administrative_division, type: :commune, type_insee: "commune_#{commune.insee}", insee: commune.insee)

    epci_ad = insert(:administrative_division, type: :epci, type_insee: "epci_#{epci.insee}", insee: epci.insee)

    region_ad =
      insert(:administrative_division, type: :region, type_insee: "region_#{region.insee}", insee: region.insee)

    d1 = insert(:dataset, declarative_spatial_areas: [departement_ad])
    d2 = insert(:dataset, declarative_spatial_areas: [commune_ad])
    d3 = insert(:dataset, declarative_spatial_areas: [epci_ad])
    d4 = insert(:dataset, declarative_spatial_areas: [region_ad])
    insert(:dataset)

    assert [d1.id, d2.id, d3.id, d4.id] ==
             %{"departement" => departement.insee}
             |> DB.Dataset.list_datasets()
             |> DB.Repo.all()
             |> Enum.map(& &1.id)
  end

  test "search by region" do
    region = insert(:region, insee: "1")
    departement = insert(:departement, region_insee: region.insee)
    commune = insert(:commune, insee: "2", region_id: region.id)
    epci = insert(:epci, insee: "3")
    insert(:commune, insee: "4", region_id: region.id, epci_insee: epci.insee)

    departement_ad =
      insert(:administrative_division,
        type: :departement,
        type_insee: "departement_#{departement.insee}",
        insee: departement.insee
      )

    commune_ad =
      insert(:administrative_division, type: :commune, type_insee: "commune_#{commune.insee}", insee: commune.insee)

    epci_ad = insert(:administrative_division, type: :epci, type_insee: "epci_#{epci.insee}", insee: epci.insee)

    region_ad =
      insert(:administrative_division, type: :region, type_insee: "region_#{region.insee}", insee: region.insee)

    d1 = insert(:dataset, population: 4, declarative_spatial_areas: [region_ad])
    d2 = insert(:dataset, population: 3, declarative_spatial_areas: [departement_ad])
    d3 = insert(:dataset, population: 2, declarative_spatial_areas: [epci_ad])
    d4 = insert(:dataset, population: 1, declarative_spatial_areas: [commune_ad])
    # Other dataset is not included
    insert(:dataset)

    assert [d1.id, d2.id, d3.id, d4.id] ==
             %{"region" => region.insee}
             |> DB.Dataset.list_datasets()
             |> DB.Repo.all()
             |> Enum.map(& &1.id)
  end

  test "search by commune" do
    departement = insert(:departement)
    region = insert(:region, insee: "1")
    epci = insert(:epci, insee: "2")

    commune =
      insert(:commune, insee: "3", departement_insee: departement.insee, region_id: region.id, epci_insee: epci.insee)

    departement_ad =
      insert(:administrative_division,
        type: :departement,
        type_insee: "departement_#{departement.insee}",
        insee: departement.insee
      )

    commune_ad =
      insert(:administrative_division, type: :commune, type_insee: "commune_#{commune.insee}", insee: commune.insee)

    epci_ad = insert(:administrative_division, type: :epci, type_insee: "epci_#{epci.insee}", insee: epci.insee)

    region_ad =
      insert(:administrative_division, type: :region, type_insee: "region_#{region.insee}", insee: region.insee)

    d1 = insert(:dataset, population: 4, declarative_spatial_areas: [region_ad])
    d2 = insert(:dataset, population: 3, declarative_spatial_areas: [departement_ad])
    d3 = insert(:dataset, population: 2, declarative_spatial_areas: [epci_ad])
    d4 = insert(:dataset, population: 1, declarative_spatial_areas: [commune_ad])
    # Other dataset is not included
    insert(:dataset)

    assert [d1.id, d2.id, d3.id, d4.id] ==
             %{"commune" => commune.insee}
             |> DB.Dataset.list_datasets()
             |> DB.Repo.all()
             |> Enum.map(& &1.id)
  end

  test "search by EPCI" do
    epci = insert(:epci, insee: "1")
    departement = insert(:departement)
    region = insert(:region, insee: "2")

    commune =
      insert(:commune, insee: "3", departement_insee: departement.insee, region_id: region.id, epci_insee: epci.insee)

    departement_ad =
      insert(:administrative_division,
        type: :departement,
        type_insee: "departement_#{departement.insee}",
        insee: departement.insee
      )

    commune_ad =
      insert(:administrative_division, type: :commune, type_insee: "commune_#{commune.insee}", insee: commune.insee)

    epci_ad = insert(:administrative_division, type: :epci, type_insee: "epci_#{epci.insee}", insee: epci.insee)

    region_ad =
      insert(:administrative_division, type: :region, type_insee: "region_#{region.insee}", insee: region.insee)

    d1 = insert(:dataset, population: 4, declarative_spatial_areas: [region_ad])
    d2 = insert(:dataset, population: 3, declarative_spatial_areas: [departement_ad])
    d3 = insert(:dataset, population: 2, declarative_spatial_areas: [epci_ad])
    d4 = insert(:dataset, population: 1, declarative_spatial_areas: [commune_ad])
    # Other dataset is not included
    insert(:dataset)

    assert [d1.id, d2.id, d3.id, d4.id] ==
             %{"epci" => epci.insee}
             |> DB.Dataset.list_datasets()
             |> DB.Repo.all()
             |> Enum.map(& &1.id)
  end
end
