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

  test "GET /datasets/aom/4242", %{conn: conn} do
    conn = conn |> get(dataset_path(conn, :by_aom, 4242))
    assert html_response(conn, 200) =~ "AOM"
    assert html_response(conn, 200) =~ "Angers Métropôle"
  end

  test "GET /datasets/aom/999999", %{conn: conn} do
    # searching for an unknown AOM should lead to a 404
    conn = conn |> get(dataset_path(conn, :by_aom, 999_999))
    assert html_response(conn, 404)
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

  test "searching for datasets in an AOM" do
    aom = insert(:aom)
    aom2 = insert(:aom)
    %Dataset{id: dataset_id, aom_id: aom_id} = insert(:dataset, legal_owners_aom: [aom, aom2], is_active: true)

    aom_ids = [aom.id, aom2.id, aom_id]
    assert aom_ids |> MapSet.new() |> Enum.count() == Enum.count(aom_ids)

    aom_ids
    |> Enum.each(fn aom_id ->
      assert [%Dataset{id: ^dataset_id}] = %{"aom" => to_string(aom_id)} |> Dataset.list_datasets() |> Repo.all()
    end)

    # Search order: datasets associated to an AOM are displayed first
    %Dataset{id: dataset2_id} = insert(:dataset, aom: aom2)

    assert [%Dataset{id: ^dataset2_id}, %Dataset{id: ^dataset_id}] =
             %{"aom" => to_string(aom2.id)} |> Dataset.list_datasets() |> Repo.all()
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

  test "datasets associated to a region are displayed first when searching for a region" do
    aom_dataset = insert(:dataset, is_active: true)
    refute is_nil(aom_dataset.aom_id)
    aom = DB.Repo.get!(DB.AOM, aom_dataset.aom_id)
    region_dataset = insert(:dataset, region_id: aom.region_id, is_active: true)

    list_datasets = fn %{} = args ->
      args |> Dataset.list_datasets() |> Repo.all() |> Enum.map(& &1.id)
    end

    assert [region_dataset.id, aom_dataset.id] == list_datasets.(%{"region" => aom.region_id |> to_string()})
    assert list_datasets.(%{}) != list_datasets.(%{"region" => aom.region_id |> to_string()})
  end

  test "datasets associated to a region are displayed last when searching for a commune" do
    aom = insert(:aom, region: region = insert(:region))
    commune = insert(:commune, aom_res_id: aom.composition_res_id, insee: "33400", region: region)

    region_dataset = insert(:dataset, region_id: region.id, is_active: true)
    aom_dataset = insert(:dataset, is_active: true, aom: aom)

    list_datasets = fn %{} = args ->
      args |> Dataset.list_datasets() |> Repo.all() |> Enum.map(& &1.id)
    end

    assert [aom_dataset.id, region_dataset.id] == list_datasets.(%{"insee_commune" => commune.insee |> to_string()})
    assert list_datasets.(%{}) != list_datasets.(%{"insee_commune" => commune.insee |> to_string()})
  end

  test "when searching for a region, use the population to sort" do
    small_aom = insert(:aom, region: region = insert(:region), population: 100)
    big_aom = insert(:aom, region: region, population: 200)

    # regional dataset: first result expected
    region_dataset = insert(:dataset, region_id: region.id, is_active: true, population: 0)
    # small population: last result expected
    aom_dataset_0 = insert(:dataset, is_active: true, aom: small_aom, custom_title: "AAA Plomberie")
    # equal population, alphabetical order expected
    aom_dataset_1 = insert(:dataset, is_active: true, aom: big_aom, custom_title: "ABC Plomberie")
    aom_dataset_2 = insert(:dataset, is_active: true, aom: big_aom, custom_title: "BBB Plomberie")

    list_datasets = fn %{} = args ->
      args |> Dataset.list_datasets() |> Repo.all() |> Enum.map(& &1.id)
    end

    assert [region_dataset.id, aom_dataset_1.id, aom_dataset_2.id, aom_dataset_0.id] ==
             list_datasets.(%{"region" => region.id |> to_string()})

    assert list_datasets.(%{}) != list_datasets.(%{"region" => region.id |> to_string()})
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
    insert(:commune, insee: "3", departement_insee: departement.insee, region_insee: region.insee)

    departement_ad = insert(:administrative_division, type: :departement, type_insee: "departement_#{departement.insee}", insee: departement.insee)
    commune_ad = insert(:administrative_division, type: :commune, type_insee: "commune_#{commune.insee}", insee: commune.insee)
    epci_ad = insert(:administrative_division, type: :epci, type_insee: "epci_#{epci.insee}", insee: epci.insee)
    region_ad = insert(:administrative_division, type: :region, type_insee: "region_#{region.insee}", insee: region.insee)

    d1 = insert(:dataset, declarative_spatial_areas: [departement_ad])
    d2 = insert(:dataset, declarative_spatial_areas: [commune_ad])
    d3 = insert(:dataset, declarative_spatial_areas: [epci_ad])
    d4 = insert(:dataset, declarative_spatial_areas: [region_ad])
    insert(:dataset)

    assert [d1.id, d2.id, d3.id, d4.id] ==
             %{"insee_departement" => departement.insee}
             |> DB.Dataset.list_datasets()
             |> DB.Repo.all()
             |> Enum.map(& &1.id)
  end
end
