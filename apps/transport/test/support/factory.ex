defmodule DB.Factory do
  @moduledoc """
  Very preliminary use of ExMachina to generate test records.
  We should figure out how to use changeset validations here, but
  so far various troubles have been met.
  """
  use ExMachina.Ecto, repo: DB.Repo

  # Ecto records

  def departement_factory do
    %DB.Departement{
      insee: "38",
      nom: "Isère",
      geom: %Geo.Polygon{
        coordinates: [
          [
            {55.0, 3.0},
            {60.0, 3.0},
            {60.0, 5.0},
            {55.0, 5.0},
            {55.0, 3.0}
          ]
        ],
        srid: 4326,
        properties: %{}
      },
      zone: "metro"
    }
  end

  def region_factory do
    %DB.Region{
      nom: sequence("region_nom")
    }
  end

  def aom_factory do
    %DB.AOM{
      insee_commune_principale: "38185",
      nom: "Grenoble",
      siren: "253800825",
      region: build(:region),
      population: 1_000
    }
  end

  def dataset_factory do
    %DB.Dataset{
      created_at: DateTime.utc_now(),
      last_update: DateTime.utc_now(),
      datagouv_title: "Hello",
      custom_title: "Hello",
      slug: sequence(:slug, fn i -> "dataset_slug_#{i}" end),
      datagouv_id: sequence(:datagouv_id, fn i -> "dataset_datagouv_id_#{i}" end),
      organization_id: sequence(:organization_id, fn i -> "dataset_organization_id_#{i}" end),
      licence: "lov2",
      tags: [],
      type: "public-transit",
      logo: "https://example.com/#{Ecto.UUID.generate()}_small.png",
      full_logo: "https://example.com/#{Ecto.UUID.generate()}.png",
      frequency: "daily",
      has_realtime: false,
      is_active: true,
      is_hidden: false,
      nb_reuses: Enum.random(0..10)
    }
  end

  def dataset_monthly_metric_factory do
    %DB.DatasetMonthlyMetric{}
  end

  def dataset_follower_factory do
    %DB.DatasetFollower{}
  end

  def resource_monthly_metric_factory do
    %DB.ResourceMonthlyMetric{}
  end

  def resource_factory do
    %DB.Resource{
      last_import: DateTime.utc_now(),
      last_update: DateTime.utc_now(),
      title: "GTFS.zip",
      counter_cache: %{},
      # NOTE: we should use real urls here (but something safe on localhost?)
      latest_url: "url",
      url: "url",
      type: "main",
      datagouv_id: Ecto.UUID.generate()
    }
  end

  def resource_history_factory do
    %DB.ResourceHistory{
      datagouv_id: "resource_datagouv_id_123",
      payload: %{}
    }
  end

  def data_conversion_factory do
    %DB.DataConversion{
      status: :success,
      converter: "my_converter",
      converter_version: Ecto.UUID.generate()
    }
  end

  def resource_unavailability_factory do
    %DB.ResourceUnavailability{}
  end

  def metrics_factory do
    %DB.Metrics{}
  end

  def commune_factory do
    %DB.Commune{
      nom: "Ballans",
      insee: "17031"
    }
  end

  def epci_factory do
    %DB.EPCI{}
  end

  def data_import_factory do
    %DB.DataImport{}
  end

  def gtfs_stop_times_factory do
    %DB.GTFS.StopTimes{}
  end

  def gtfs_trips_factory do
    %DB.GTFS.Trips{}
  end

  def gtfs_calendar_factory do
    %DB.GTFS.Calendar{}
  end

  def gtfs_calendar_dates_factory do
    %DB.GTFS.CalendarDates{}
  end

  def geo_data_import_factory do
    %DB.GeoDataImport{}
  end

  def geo_data_factory do
    %DB.GeoData{}
  end

  def multi_validation_factory do
    %DB.MultiValidation{validator: "validator", validation_timestamp: DateTime.utc_now()}
  end

  def resource_metadata_factory do
    %DB.ResourceMetadata{}
  end

  def dataset_history_factory do
    %DB.DatasetHistory{}
  end

  def dataset_history_resources_factory do
    %DB.DatasetHistoryResources{}
  end

  def notification_factory do
    %DB.Notification{}
  end

  def gtfs_stops_factory do
    %DB.GTFS.Stops{}
  end

  def dataset_score_factory do
    %DB.DatasetScore{}
  end

  # Non-Ecto stuff, for now kept here for convenience

  def datagouv_api_get_factory do
    %{
      "title" => "some title"
    }
  end

  def administrative_division_factory do
    %DB.AdministrativeDivision{
      insee: "38",
      type_insee: "departement_38",
      type: :departement,
      nom: "Isère",
      population: 0,
      geom: %Geo.Polygon{
        coordinates: [
          [
            {55.0, 3.0},
            {60.0, 3.0},
            {60.0, 5.0},
            {55.0, 5.0},
            {55.0, 3.0}
          ]
        ],
        srid: 4326,
        properties: %{}
      }
    }
  end

  @doc """
  Useful function to insert in one call everything needed for resource related tests.
  A dataset, a resource, a resource history, a multi_validation, some metadata
  For the moment, it inserts GTFS resources, but could be extended to insert any resource type and validation.

  Usage:
  insert_resource_and_friends(~D[2022-07-12], [])
  => insert an active dataset, a resource, a resource history, a validation, a metadata.
  Metadata contains the end date provided.

  insert_resource_and_friends(~D[2022-07-12], [is_active: false])
  => same as above, but the dataset is inactive

  insert_resource_and_friends(~D[2022-07-12], [resource_available: false])
  => resource is inserted with is_available = false

  insert_resource_and_friends(~D[2022-07-12], [resource_history_payload: %{"url" => "xxx"}])
  => specify resource_history payload

  insert_resource_and_friends(~D[2022-07-12], [dataset: dataset_1])
  => provide an already existing dataset. Useful when inserting a second resource linked to a dataset.

  The function returns a map with all the created DB structures
  """
  def insert_resource_and_friends(end_date, opts \\ []) do
    def_opts = [resource_available: true, is_active: true, resource_history_payload: %{}]
    opts = Keyword.merge(def_opts, opts)

    dataset_opts =
      [
        is_active: Keyword.get(opts, :is_active),
        has_realtime: Keyword.get(opts, :has_realtime),
        type: Keyword.get(opts, :type),
        custom_title: Keyword.get(opts, :custom_title)
      ]
      |> Enum.reject(fn {_, v} -> is_nil(v) end)

    dataset = Keyword.get(opts, :dataset, insert(:dataset, dataset_opts))

    %{id: resource_id} =
      resource =
      Keyword.get(
        opts,
        :resource,
        insert(:resource,
          dataset_id: dataset.id,
          is_available: Keyword.get(opts, :resource_available),
          is_community_resource: Keyword.get(opts, :is_community_resource, false),
          format: "GTFS",
          datagouv_id: Ecto.UUID.generate()
        )
      )

    resource_history =
      insert(:resource_history, resource_id: resource_id, payload: Keyword.get(opts, :resource_history_payload))

    multi_validation =
      insert(:multi_validation,
        validator: Transport.Validators.GTFSTransport.validator_name(),
        resource_history_id: resource_history.id,
        max_error: Keyword.get(opts, :max_error, "NoError"),
        digest: %{
          "max_severity" => %{"max_level" => Keyword.get(opts, :max_error, "NoError"), "worst_occurrences" => 0}
        }
      )

    resource_metadata =
      insert(:resource_metadata,
        multi_validation_id: multi_validation.id,
        metadata: %{"start_date" => end_date |> Date.add(-60), "end_date" => end_date},
        modes: Keyword.get(opts, :modes),
        features: Keyword.get(opts, :features)
      )

    %{
      dataset: dataset,
      resource: resource,
      resource_history: resource_history,
      multi_validation: multi_validation,
      resource_metadata: resource_metadata
    }
  end

  def insert_up_to_date_resource_and_friends(opts \\ []) do
    insert_resource_and_friends(Date.utc_today() |> Date.add(30), opts)
  end

  def insert_outdated_resource_and_friends(opts \\ []) do
    insert_resource_and_friends(Date.utc_today() |> Date.add(-5), opts)
  end

  def insert_notification(%{dataset: %DB.Dataset{id: dataset_id, datagouv_id: datagouv_id}} = args) do
    args
    |> Map.delete(:dataset)
    |> Map.merge(%{dataset_id: dataset_id, dataset_datagouv_id: datagouv_id})
    |> insert_notification()
  end

  def insert_notification(args) do
    notification = %DB.Notification{} |> DB.Notification.changeset(args) |> DB.Repo.insert!()

    case Map.get(args, :inserted_at) do
      nil -> notification
      %DateTime{} = dt -> notification |> Ecto.Changeset.change(%{inserted_at: dt}) |> DB.Repo.update!()
    end
  end

  def notification_subscription_factory do
    %DB.NotificationSubscription{}
  end

  def hidden_reuser_alert_factory do
    %DB.HiddenReuserAlert{}
  end

  def resource_related_factory do
    %DB.ResourceRelated{}
  end

  def default_token_factory do
    %DB.DefaultToken{}
  end

  def reuser_improved_data_factory do
    dataset = build(:dataset)

    %DB.ReuserImprovedData{
      dataset: dataset,
      resource: build(:resource, dataset_id: dataset.id),
      contact: insert_contact(),
      organization: build(:organization),
      download_url: sequence(:download_url, fn i -> "https://example.com/file_#{i}" end)
    }
  end

  def organization_factory do
    %DB.Organization{
      id: Ecto.UUID.generate(),
      badges: [],
      logo: "https://example.com/#{Ecto.UUID.generate()}.small.png",
      logo_thumbnail: "https://example.com/#{Ecto.UUID.generate()}.small.png",
      name: sequence(:name, fn i -> "organization_name_#{i}" end),
      slug: sequence(:slug, fn i -> "organization_slug_#{i}" end)
    }
  end

  def reuse_factory do
    %DB.Reuse{
      datagouv_id: sequence(:datagouv_id, &"datagouv_id-#{&1}"),
      title: sequence(:title, &"Reuse Title #{&1}"),
      slug: sequence(:slug, &"reuse-slug-#{&1}"),
      url: sequence(:url, &"http://example.com/reuse/#{&1}"),
      type: "api",
      description: "A description of the reuse.",
      remote_url: sequence(:remote_url, &"http://remote.example.com/reuse/#{&1}"),
      organization: "Example Organization",
      organization_id: sequence(:organization_id, &"org-#{&1}"),
      owner: "Example Owner",
      owner_id: sequence(:owner_id, &"owner-#{&1}"),
      image: sequence(:image, &"http://example.com/image/#{&1}.jpg"),
      featured: false,
      archived: false,
      topic: "transport_and_mobility",
      tags: ["tag1", "tag2"],
      metric_discussions: 0,
      metric_datasets: 0,
      metric_followers: 0,
      metric_views: 0,
      created_at: DateTime.utc_now(),
      last_modified: DateTime.utc_now()
    }
  end

  def offer_factory do
    %DB.Offer{
      nom_commercial: sequence(:nom_commercial, &"nom_commercial-#{&1}"),
      identifiant_offre: sequence(:identifiant_offre, & &1),
      type_transport: "Transport urbain",
      modes: ["Bus"],
      nom_aom: sequence(:nom_aom, &"nom_aom-#{&1}"),
      aom_siren: sequence(:aom_siren, &"aom_siren-#{&1}"),
      niveau: "Local",
      exploitant: "Keolis",
      type_contrat: "",
      territoire: sequence(:territoire, &"territoire-#{&1}")
    }
  end

  def insert_token(%{} = args \\ %{}) do
    args =
      %{
        secret: "secret",
        name: "name",
        contact_id: insert_contact().id
      }
      |> Map.merge(args)

    # Insert an organization only if `organization_id` was not passed
    args =
      if Map.has_key?(args, :organization_id) do
        args
      else
        Map.merge(args, %{organization_id: insert(:organization).id})
      end

    DB.Token.changeset(%DB.Token{}, args) |> DB.Repo.insert!()
  end

  def insert_contact(%{} = args \\ %{}) do
    %{
      first_name: "John",
      last_name: "Doe",
      email: "john#{Ecto.UUID.generate()}@example.fr",
      job_title: "Boss",
      organization: "Big Corp Inc",
      phone_number: "06 82 22 88 03",
      creation_source: "admin"
    }
    |> Map.merge(args)
    |> DB.Contact.insert!()
  end

  def insert_irve_dataset do
    insert(:dataset, %{
      type: "charging-stations",
      custom_title: "Infrastructures de Recharge pour Véhicules Électriques - IRVE",
      organization: "data.gouv.fr",
      organization_id: "646b7187b50b2a93b1ae3d45"
    })
  end

  def insert_bnlc_dataset do
    insert(:dataset, %{
      type: "carpooling-areas",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label),
      organization_id: "5abca8d588ee386ee6ece479"
    })
  end

  def insert_parcs_relais_dataset do
    insert(:dataset, %{
      type: "road-data",
      custom_title: "Base nationale des parcs relais",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label),
      organization_id: "5abca8d588ee386ee6ece479"
    })
  end

  def insert_zfe_dataset do
    insert(:dataset, %{
      type: "road-data",
      custom_title: "Base Nationale des Zones à Faibles Émissions (BNZFE)",
      organization: Application.fetch_env!(:transport, :datagouvfr_transport_publisher_label),
      organization_id: "5abca8d588ee386ee6ece479",
      datagouv_id: "zfe_fake_dataset_id"
    })
  end

  def insert_imported_irve_geo_data(dataset_id) do
    %{id: resource_history_id} = insert(:resource_history, %{payload: %{"dataset_id" => dataset_id}})
    %{id: geo_data_import_id} = insert(:geo_data_import, %{slug: :irve, resource_history_id: resource_history_id})

    insert(:geo_data, %{
      geo_data_import_id: geo_data_import_id,
      geom: %Geo.Point{coordinates: {1, 1}, srid: 4326},
      payload: %{
        "nom_enseigne" => "Recharge Super 95",
        "id_station_itinerance" => "FRELCPEYSPC",
        "nom_station" => "Dehaven Centre",
        "nbre_pdc" => 2
      }
    })

    insert(:geo_data, %{
      geo_data_import_id: geo_data_import_id,
      geom: %Geo.Point{coordinates: {2, 2}, srid: 4326},
      payload: %{
        "nom_enseigne" => "Recharge Super 95",
        "id_station_itinerance" => "FRELCPBLOHM",
        "nom_station" => "Gemina Port",
        "nbre_pdc" => 3
      }
    })
  end

  def generate_dataset_payload(datagouv_id, resources \\ nil) do
    datagouv_dataset_response(%{"id" => datagouv_id, "resources" => resources || generate_resources_payload()})
  end

  def datagouv_dataset_response(%{} = attributes \\ %{}) do
    Map.merge(
      %{
        "id" => Ecto.UUID.generate(),
        "title" => "dataset",
        "created_at" => DateTime.utc_now() |> to_string(),
        "last_update" => DateTime.utc_now() |> to_string(),
        "slug" => "dataset-slug",
        "license" => "lov2",
        "frequency" => "daily",
        "tags" => [],
        "organization" => %{
          "id" => Ecto.UUID.generate(),
          "name" => "Org " <> Ecto.UUID.generate(),
          "badges" => [],
          "logo" => "https://example.com/img.jpg",
          "logo_thumbnail" => "https://example.com/img.small.jpg",
          "slug" => Ecto.UUID.generate()
        }
      },
      attributes
    )
  end

  def generate_resources_payload(opts \\ []) do
    [generate_resource_payload(opts)]
  end

  def generate_resource_payload(opts \\ []) do
    %{
      "title" => Keyword.get(opts, :title, "resource1"),
      "url" => Keyword.get(opts, :url, "http://localhost:4321/resource1"),
      "id" => Keyword.get(opts, :id, "resource1_id"),
      "type" => "main",
      "filetype" => Keyword.get(opts, :filetype, "remote"),
      "format" => Keyword.get(opts, :format, "zip"),
      "last_modified" => DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.to_iso8601(),
      "schema" => %{"name" => Keyword.get(opts, :schema_name), "version" => Keyword.get(opts, :schema_version)}
    }
  end

  defmodule IRVE do
    @moduledoc """
    Factory part relevant to IRVE.
    """

    @doc """
    Generate a row following the IRVE static schema.

    See:
    - https://schema.data.gouv.fr/etalab/schema-irve-statique/
    """
    def generate_row(overrides \\ %{}) do
      %{
        "nom_amenageur" => "Métropole de Nulle Part",
        "siren_amenageur" => "123456782",
        "contact_amenageur" => "amenageur@example.com",
        "nom_operateur" => "Opérateur de Charge",
        "contact_operateur" => "operateur@example.com",
        "telephone_operateur" => "0199456782",
        "nom_enseigne" => "Réseau de recharge",
        "id_station_itinerance" => "FRPAN99P12345678",
        "id_station_local" => "station_001",
        "nom_station" => "Ma Station",
        "implantation_station" => "Voirie",
        "adresse_station" => "26 rue des écluses, 17430 Champdolent",
        "code_insee_commune" => "17085",
        "coordonneesXY" => "[-0.799141,45.91914]",
        "nbre_pdc" => 1,
        "id_pdc_itinerance" => "FRPAN99E12345678",
        "id_pdc_local" => "pdc_001",
        "puissance_nominale" => 22,
        "prise_type_ef" => false,
        "prise_type_2" => true,
        "prise_type_combo_ccs" => false,
        "prise_type_chademo" => false,
        "prise_type_autre" => false,
        "gratuit" => false,
        "paiement_acte" => true,
        "paiement_cb" => true,
        "paiement_autre" => true,
        "tarification" => "2,50€ / 30min puis 0,025€ / minute",
        "condition_acces" => "Accès libre",
        "reservation" => false,
        "horaires" => "24/7",
        "accessibilite_pmr" => "Accessible mais non réservé PMR",
        "restriction_gabarit" => "Hauteur maximale 2.30m",
        "station_deux_roues" => false,
        "raccordement" => "Direct",
        "num_pdl" => "12345678912345",
        "date_mise_en_service" => "2024-10-02",
        "observations" => "Station située au niveau -1 du parking",
        "date_maj" => "2024-10-17",
        "cable_t2_attache" => false
      }
      |> Map.merge(overrides)
    end

    def to_csv_body(items), do: items |> CSV.encode(headers: true) |> Enum.join()

    def build_datagouv_initial_pagination_payload(page_size: page_size) do
      %{
        "data" => [],
        "next_page" => nil,
        "page" => 1,
        "total" => 1,
        "page_size" => page_size
      }
    end

    @doc """
    Build a typical data gouv API (list datasets) response.

    If you need to verify or modify the payload, see examples at:
    - https://www.data.gouv.fr/api/1/datasets/?page=1&page_size=20&schema=etalab%2Fschema-irve-statique
    - https://doc.data.gouv.fr/api/reference/#/datasets/list_datasets
    """
    def build_datagouv_page_payload do
      %{
        "data" => [
          %{
            "id" => "the-dataset-id",
            "title" => "the-dataset-title",
            "organization" => %{
              "id" => "the-org-id",
              "name" => "the-org",
              "page" => "http://the-org"
            },
            "resources" => [
              %{
                "schema" => %{
                  "name" => "etalab/schema-irve-statique",
                  "version" => "2.3.0"
                },
                "id" => "the-resource-id",
                "title" => "the-resource-title",
                "extras" => %{
                  "validation-report:valid_resource" => true,
                  "validation-report:validation_date" => "2024-02-24"
                },
                "filetype" => "file",
                "last_modified" => "2024-02-29T07:43:59.660000+00:00",
                "url" => "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv"
              }
            ]
          },
          %{
            "id" => "another-dataset-id",
            "title" => "another-dataset-title",
            "organization" => %{
              "id" => "another-org-id",
              "name" => "another-org",
              "page" => "http://another-org"
            },
            "resources" => [
              %{
                "schema" => %{
                  "name" => "etalab/schema-irve-statique",
                  "version" => "2.3.0"
                },
                "id" => "another-resource-id",
                "title" => "another-resource-title",
                "extras" => %{
                  "validation-report:valid_resource" => true,
                  "validation-report:validation_date" => "2024-02-24"
                },
                "filetype" => "file",
                "last_modified" => "2024-02-29T07:43:59.660000+00:00",
                "url" => "https://static.data.gouv.fr/resources/another-irve-url-2024/data.csv"
              }
            ]
          },
          %{
            "id" => "individual-published-dataset-id",
            "title" => "individual-published-dataset-title",
            "organization" => nil,
            "owner" => "Guy who loves IRVE",
            "resources" => [
              %{
                "schema" => %{
                  "name" => "etalab/schema-irve-statique",
                  "version" => "2.3.0"
                },
                "id" => "individual-published-resource-id",
                "title" => "individual-published-resource-title",
                "extras" => %{
                  "validation-report:valid_resource" => true,
                  "validation-report:validation_date" => "2024-02-24"
                },
                "filetype" => "file",
                "last_modified" => "2024-02-29T07:43:59.660000+00:00",
                "url" => "https://static.data.gouv.fr/resources/individual-published-irve-url-2024/data.csv"
              }
            ]
          }
        ]
      }
    end
  end
end
