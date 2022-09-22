defmodule Transport.ImportDataTest do
  # NOTE: temporarily set to false, until it doesn't use with_mock anymore
  use ExUnit.Case, async: false
  alias Transport.ImportData
  import Mock
  import DB.Factory
  import ExUnit.CaptureLog
  import Ecto.Query
  doctest ImportData, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)

    # The national dataset is pre-inserted in the DB via a migration
    assert DB.Region |> where([r], r.nom == "National") |> DB.Repo.aggregate(:count) == 1

    :ok
  end

  setup do
    Mox.stub_with(Transport.HTTPoison.Mock, HTTPoison)
    Mox.stub_with(Transport.AvailabilityChecker.Mock, Transport.AvailabilityChecker)
    Mox.stub_with(Hasher.Mock, Hasher.Dummy)
    :ok
  end

  def generate_resources_payload(
        title \\ nil,
        url \\ nil,
        id \\ nil,
        schema_name \\ nil,
        schema_version \\ nil,
        filetype \\ nil
      ) do
    [
      %{
        "title" => title || "resource1",
        "url" => url || "http://localhost:4321/resource1",
        "id" => id || "resource1_id",
        "type" => "main",
        "filetype" => filetype || "remote",
        "schema" => %{"name" => schema_name, "version" => schema_version}
      }
    ]
  end

  def generate_dataset_payload(datagouv_id, resources \\ nil) do
    resources = resources || generate_resources_payload()

    %{
      "title" => "dataset1",
      "id" => datagouv_id,
      "slug" => "dataset-slug",
      "resources" => resources
    }
  end

  def insert_national_dataset(datagouv_id) do
    {:ok, changes} =
      DB.Dataset.changeset(%{
        "datagouv_id" => datagouv_id,
        "slug" => "ma_limace",
        "national_dataset" => "true"
      })

    DB.Repo.insert!(changes)
  end

  def http_get_mock_200(datagouv_id, payload \\ nil) do
    fn url, [], hackney: [follow_redirect: true] ->
      base_url = Application.fetch_env!(:transport, :datagouvfr_site)
      expected_url = "#{base_url}/api/1/datasets/#{datagouv_id}/"
      assert url == expected_url

      payload = payload || generate_dataset_payload(datagouv_id)

      %HTTPoison.Response{body: Jason.encode!(payload), status_code: 200}
    end
  end

  def http_get_mock_404(datagouv_id) do
    fn url, [], hackney: [follow_redirect: true] ->
      base_url = Application.fetch_env!(:transport, :datagouvfr_site)
      expected_url = "#{base_url}/api/1/datasets/#{datagouv_id}/"
      assert url == expected_url

      %HTTPoison.Response{body: "erreur 404, page non trouvée", status_code: 404}
    end
  end

  def http_stream_mock do
    fn _url ->
      {:ok,
       %{
         status: 200,
         hash: "resource1_hash"
       }}
    end
  end

  def http_head_mock do
    fn _url, _, _ ->
      {:ok, %HTTPoison.Response{status_code: 200}}
    end
  end

  def db_count(type) do
    DB.Repo.aggregate(type, :count, :id)
  end

  test "hello world des imports" do
    insert_national_dataset(datagouv_id = "dataset1_id")

    assert db_count(DB.Dataset) == 1
    assert db_count(DB.Resource) == 0

    with_mock HTTPoison, get!: http_get_mock_200(datagouv_id), head: http_head_mock() do
      with_mock Datagouvfr.Client.CommunityResources, get: fn _ -> {:ok, []} end do
        with_mock HTTPStreamV2, fetch_status_and_hash: http_stream_mock() do
          logs = capture_log([level: :info], fn -> ImportData.import_all_datasets() end)

          assert_called_exactly(HTTPoison.get!(:_, :_, :_), 1)

          # for each resource, 1 head request is made to check for availability
          assert_called_exactly(HTTPoison.head(:_, :_, :_), 1)
          assert_called_exactly(Datagouvfr.Client.CommunityResources.get(:_), 1)

          # import is a success
          assert logs =~ "all datasets have been reimported (0 failures / 1)"
        end
      end
    end

    assert db_count(DB.Dataset) == 1
    assert db_count(DB.Resource) == 1
  end

  test "import fails when datagouv responds a 404" do
    insert_national_dataset(datagouv_id = "dataset1_id")

    assert db_count(DB.Dataset) == 1
    assert db_count(DB.Resource) == 0

    with_mock HTTPoison, get!: http_get_mock_404(datagouv_id), head: http_head_mock() do
      with_mock Datagouvfr.Client.CommunityResources, get: fn _ -> {:ok, []} end do
        with_mock HTTPStreamV2, fetch_status_and_hash: http_stream_mock() do
          logs = capture_log([level: :info], fn -> ImportData.import_all_datasets() end)
          assert_called_exactly(HTTPoison.get!(:_, :_, :_), 1)
          assert logs =~ "all datasets have been reimported (1 failures / 1)"
        end
      end
    end

    assert db_count(DB.Dataset) == 1
    assert db_count(DB.Resource) == 0
  end

  test "what happens with resources when a dataset is reimported multiple times" do
    insert_national_dataset(datagouv_id = "dataset1_id")

    assert db_count(DB.Dataset) == 1
    assert db_count(DB.Resource) == 0

    with_mock HTTPoison, get!: http_get_mock_200(datagouv_id), head: http_head_mock() do
      with_mock Datagouvfr.Client.CommunityResources, get: fn _ -> {:ok, []} end do
        with_mock HTTPStreamV2, fetch_status_and_hash: http_stream_mock() do
          ImportData.import_all_datasets()
        end
      end
    end

    assert db_count(DB.Dataset) == 1

    [resource] = DB.Resource |> DB.Repo.all()
    assert Map.get(resource, :title) == "resource1"
    assert Map.get(resource, :filetype) == "remote"
    assert Map.get(resource, :type) == "main"
    assert Map.get(resource, :display_position) == 0
    resource_id = Map.get(resource, :id)

    # set the metadata field for this resource
    saved_metadata = %{"foo" => "bar"}
    resource |> DB.Resource.changeset(%{metadata: saved_metadata}) |> DB.Repo.update!()

    # import 2
    payload_2 =
      generate_dataset_payload(
        datagouv_id,
        generate_resources_payload(
          new_title = "new title !!! fresh !!!",
          "http://localhost:4321/resource1",
          new_datagouv_id = "resource2_id"
        )
      )

    with_mock HTTPoison, get!: http_get_mock_200(datagouv_id, payload_2), head: http_head_mock() do
      with_mock Datagouvfr.Client.CommunityResources, get: fn _ -> {:ok, []} end do
        with_mock HTTPStreamV2, fetch_status_and_hash: http_stream_mock() do
          ImportData.import_all_datasets()
        end
      end
    end

    assert db_count(DB.Dataset) == 1

    [resource_updated] = DB.Resource |> DB.Repo.all()
    # assert that the resource has been updated with a new title and a new datagouv_id
    # but its id is still the same
    assert Map.get(resource_updated, :title) == new_title
    assert Map.get(resource_updated, :id) == resource_id
    assert Map.get(resource_updated, :datagouv_id) == new_datagouv_id

    # previous metadata was kept
    assert Map.get(resource_updated, :metadata) == saved_metadata

    # import 3
    payload_3 =
      generate_dataset_payload(
        datagouv_id,
        generate_resources_payload(
          new_title,
          _new_url = "https://example.com/" <> Ecto.UUID.generate(),
          new_datagouv_id
        )
      )

    with_mock HTTPoison, get!: http_get_mock_200(datagouv_id, payload_3), head: http_head_mock() do
      with_mock Datagouvfr.Client.CommunityResources, get: fn _ -> {:ok, []} end do
        with_mock HTTPStreamV2, fetch_status_and_hash: http_stream_mock() do
          ImportData.import_all_datasets()
        end
      end
    end

    assert db_count(DB.Dataset) == 1

    # we still have only one resource
    [resource_updated] = DB.Resource |> DB.Repo.all()

    # the resource is up-to-date with data.gouv
    assert Map.get(resource_updated, :title) == new_title
    assert Map.get(resource_updated, :datagouv_id) == new_datagouv_id
    assert Map.get(resource_updated, :display_position) == 0

    # and the internal resource.id did not change
    assert Map.get(resource_updated, :id) == resource_id
  end

  test "import dataset with a community resource" do
    insert_national_dataset(datagouv_id = "dataset1_id")
    assert db_count(DB.Dataset) == 1
    assert db_count(DB.Resource) == 0

    community_resource_title = "a_community_resource"
    schema_name = "etalab/covoiturage"
    schema_version = "v1.0"

    with_mock HTTPoison,
      get!: http_get_mock_200(datagouv_id, generate_dataset_payload(datagouv_id, [])),
      head: http_head_mock() do
      with_mock Datagouvfr.Client.CommunityResources,
        get: fn _ ->
          {:ok,
           generate_resources_payload(
             community_resource_title,
             "http://example.com/file",
             "1",
             schema_name,
             schema_version
           )}
        end do
        with_mock HTTPStreamV2, fetch_status_and_hash: http_stream_mock() do
          ImportData.import_all_datasets()
        end
      end
    end

    [resource] = DB.Resource |> where([r], r.is_community_resource) |> DB.Repo.all()
    assert Map.get(resource, :title) == community_resource_title
    assert Map.get(resource, :schema_name) == schema_name
    assert Map.get(resource, :schema_version) == schema_version
    assert Map.get(resource, :display_position) == 0
  end

  # test "error while connecting to datagouv server"

  # test "with community resources"

  describe "import_all_test" do
    test "logs unmanaged exceptions" do
      # NOTE: we should ultimately use "valid" datasets (which went through the changesets),
      # because currently this is not the case
      insert(:dataset, datagouv_id: "some-id")
      assert DB.Repo.aggregate(DB.Dataset, :count, :id) == 1

      # For now, using mocking as an intermediate step to using a real separate mock udata implementation
      # (but there's too much to refactor for now).
      payload = :datagouv_api_get |> build() |> Jason.encode!()

      mock = fn _, _, _ ->
        %HTTPoison.Response{body: payload, status_code: 200}
      end

      with_mock HTTPoison, get!: mock do
        logs =
          capture_log([level: :warn], fn ->
            ImportData.import_all_datasets()
          end)

        logs = logs |> String.split("\n")
        assert logs |> Enum.at(0) =~ "Import of dataset has failed"
        # NOTE: for now, relying on a specific error that we're triggering due to missing key, but it's
        # far from ideal and it would be better to have something more explicit
        assert logs |> Enum.at(1) =~ "no function clause matching in Transport.ImportData.get_valid_resources/2"
      end
    end
  end

  test "get valid resources" do
    m = %{
      "resources" => [
        %{"format" => "gtfs"},
        %{"format" => "netex"},
        %{"format" => "gtfs-rt"},
        %{"format" => "siri"},
        %{"format" => "siri lite"},
        %{"format" => "csv"}
      ]
    }

    valid_resources = ImportData.get_valid_resources(m, "public-transit")

    assert valid_resources |> Enum.frequencies_by(fn %{"format" => f} -> f end) == %{
             "gtfs" => 1,
             "gtfs-rt" => 1,
             "netex" => 1,
             "siri" => 1,
             "siri lite" => 1
           }
  end
end
