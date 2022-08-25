defmodule DB.ResourceTest do
  use TransportWeb.ConnCase, async: true
  alias Shared.Validation.Validator.Mock, as: ValidatorMock
  alias DB.{LogsValidation, Repo, Resource, Validation}
  import Mox
  import DB.Factory
  import Ecto.Query

  doctest Resource, import: true

  setup do
    Mox.stub_with(Transport.DataVisualization.Mock, Transport.DataVisualization.Impl)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  def http_validation_response do
    %HTTPoison.Response{
      status_code: 200,
      body:
        "{\"metadata\":{\"start_date\":\"2021-07-08\",\"end_date\":\"2021-10-24\",\"stop_areas_count\":588,\"stop_points_count\":1016,\"lines_count\":126,\"networks\":[\"Sté de Transport de l'Agglomération Nazairienne\"],\"modes\":[\"bus\"],\"issues_count\":{\"ExcessiveSpeed\":2,\"NullDuration\":10,\"DuplicateStops\":43},\"has_fares\":false,\"has_shapes\":true,\"some_stops_need_phone_agency\":false,\"some_stops_need_phone_driver\":false},\"validations\":{\"ExcessiveSpeed\":[{\"severity\":\"Information\",\"issue_type\":\"ExcessiveSpeed\",\"object_id\":\"22226\",\"object_type\":\"Stop\",\"object_name\":\"FossedeRotz\",\"related_objects\":[{\"id\":\"21994\",\"object_type\":\"Stop\",\"name\":\"FosseBlanc\"},{\"id\":\"118\",\"object_type\":\"Route\",\"name\":\"301\"}],\"details\":\"computed speed between the stops is 525.76 km/h (17525 m travelled in 120 seconds)\"}]}}"
    }
  end

  test "validate and save a resource" do
    resource = insert(:resource, %{url: "url1", format: "GTFS"})

    ValidatorMock
    |> expect(:validate_from_url, 1, fn _resource_url ->
      {:ok, %{"validations" => %{}, "metadata" => %{}}}
    end)

    assert Resource.validate_and_save(resource, false) == {:ok, nil}

    # a validation is saved in the DB
    validations = Validation |> where([v], v.resource_id == ^resource.id) |> Repo.all()
    assert length(validations) == 1

    # a log of the validation is saved as well
    [log_validation] = LogsValidation |> where([l], l.resource_id == ^resource.id) |> Repo.all()
    assert log_validation.skipped_reason == "no previous validation"
  end

  test "validate and save a GBFS resource" do
    resource = insert(:resource, %{url: "url1", format: "gbfs"})

    Transport.Shared.GBFSMetadata.Mock
    |> expect(:compute_feed_metadata, fn _resource, _cors_base_url ->
      %{"foo" => "bar", "validation" => %{"has_errors" => true}}
    end)

    assert {true, "gbfs can be validated"} == Resource.can_validate?(resource)
    assert Resource.validate_and_save(resource, false) == {:ok, nil}

    assert %Resource{
             metadata: %{"foo" => "bar", "validation" => %{"has_errors" => true}},
             validation: %Validation{details: %{"has_errors" => true}}
           } = Resource |> preload(:validation) |> Repo.get(resource.id)
  end

  test "validate and save a resource with a JSON Schema schema" do
    url = "https://example.com/file"
    schema_name = "etalab/foo"

    resource =
      insert(:resource, %{url: url, schema_name: schema_name, metadata: %{"bar" => "baz"}, content_hash: "hash"})

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{schema_name => %{}} end)

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 2, fn type ->
      case type do
        "tableschema" -> %{}
        "jsonschema" -> %{schema_name => %{}}
      end
    end)

    Shared.Validation.JSONSchemaValidator.Mock
    |> expect(:load_jsonschema_for_schema, fn _schema ->
      %ExJsonSchema.Schema.Root{
        schema: %{"properties" => %{"name" => %{"type" => "string"}}, "required" => ["name"], "type" => "object"},
        version: 7
      }
    end)

    Shared.Validation.JSONSchemaValidator.Mock
    |> expect(:validate, fn _schema, ^url ->
      %{"foo" => "bar"}
    end)

    assert {true, "schema is set"} == Resource.can_validate?(resource)
    assert {true, "schema is set and no previous validation"} == Resource.need_validate?(resource, false)
    assert Resource.validate_and_save(resource, false) == {:ok, nil}

    assert %{
             metadata: %{
               "bar" => "baz",
               "validation" => %{"foo" => "bar", "schema_type" => "jsonschema", "content_hash" => "hash"}
             },
             validation: %Validation{
               details: %{"foo" => "bar", "schema_type" => "jsonschema", "content_hash" => "hash"},
               data_vis: nil,
               max_error: nil,
               validation_latest_content_hash: nil
             }
           } = Resource |> preload(:validation) |> Repo.get(resource.id)
  end

  test "validate and save a resource with a Table Schema schema" do
    url = "https://example.com/file"
    schema_name = "etalab/foo"

    resource =
      insert(:resource, %{url: url, schema_name: schema_name, metadata: %{"bar" => "baz"}, content_hash: "hash"})

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{schema_name => %{}} end)

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 1, fn "tableschema" -> %{schema_name => %{}} end)

    Shared.Validation.TableSchemaValidator.Mock
    |> expect(:validate, fn ^schema_name, ^url, nil -> %{"foo" => "bar"} end)

    assert {true, "schema is set"} == Resource.can_validate?(resource)
    assert {true, "schema is set and no previous validation"} == Resource.need_validate?(resource, false)
    assert Resource.validate_and_save(resource, false) == {:ok, nil}

    assert %{
             metadata: %{
               "bar" => "baz",
               "validation" => %{"foo" => "bar", "schema_type" => "tableschema", "content_hash" => "hash"}
             },
             validation: %Validation{
               details: %{"foo" => "bar", "schema_type" => "tableschema", "content_hash" => "hash"},
               data_vis: nil,
               max_error: nil,
               validation_latest_content_hash: nil
             }
           } = Resource |> preload(:validation) |> Repo.get(resource.id)
  end

  test "validation is skipped if previous validation is still valid" do
    resource = insert(:resource, %{url: "url1", format: "GTFS", content_hash: "sha256_hash"})

    # we expect the validator the be called only once, as the second validation
    # should be skipped
    ValidatorMock
    |> expect(:validate_from_url, 1, fn _resource_url ->
      {:ok, %{"validations" => %{}, "metadata" => %{}}}
    end)

    # first validation
    assert {true, "GTFS can be validated"} == Resource.can_validate?(resource)
    assert Resource.validate_and_save(resource.id, false) == {:ok, nil}
    [validation] = Validation |> where([v], v.resource_id == ^resource.id) |> Repo.all()

    # Check resource hash has been correctly saved
    assert validation.validation_latest_content_hash == resource.content_hash

    # second validation, should be skipped and be a success
    assert Resource.validate_and_save(resource.id, false) == {:ok, nil}

    # check the logs are correct
    validations_logs = LogsValidation |> where([l], l.resource_id == ^resource.id) |> Repo.all()
    reasons = validations_logs |> Enum.frequencies_by(& &1.skipped_reason)
    assert reasons == %{"content hash has not changed" => 1, "no previous validation" => 1}
  end

  test "validation is re-launched after resource hash has changed" do
    resource = insert(:resource, %{url: "url1", format: "GTFS", content_hash: "sha256_hash"})

    # we expect 2 validator calls here
    ValidatorMock
    |> expect(:validate_from_url, 2, fn _resource_url ->
      {:ok, %{"validations" => %{}, "metadata" => %{}}}
    end)

    # first validation
    assert Resource.validate_and_save(resource.id, false) == {:ok, nil}

    # update resource, second validation
    resource |> Ecto.Changeset.change(%{content_hash: "new_hash"}) |> DB.Repo.update!()
    assert Resource.validate_and_save(resource.id, false) == {:ok, nil}

    # check the logs are correct
    validations_logs = LogsValidation |> where([l], l.resource_id == ^resource.id) |> Repo.all()
    reasons = validations_logs |> Enum.frequencies_by(& &1.skipped_reason)
    assert reasons == %{"content hash has changed" => 1, "no previous validation" => 1}
  end

  test "find_tags_from_metadata" do
    # Can detect all available tags
    assert ["transport à la demande"] == Resource.find_tags_from_metadata(%{"some_stops_need_phone_agency" => true})
    assert ["transport à la demande"] == Resource.find_tags_from_metadata(%{"some_stops_need_phone_driver" => true})
    assert ["description des correspondances"] == Resource.find_tags_from_metadata(%{"has_pathways" => true})
    assert ["tracés de lignes"] == Resource.find_tags_from_metadata(%{"has_shapes" => true})

    assert ["couleurs des lignes"] ==
             Resource.find_tags_from_metadata(%{"lines_with_custom_color_count" => 5, "lines_count" => 5})

    assert Resource.find_tags_from_metadata(%{"lines_with_custom_color_count" => 0, "has_fares" => false}) == []

    # Can find multiple tags
    assert Resource.find_tags_from_metadata(%{"has_fares" => true, "has_pathways" => true}) == [
             "tarifs",
             "description des correspondances"
           ]

    assert Resource.find_tags_from_metadata(%{
             "some_stops_need_phone_driver" => true,
             "some_stops_need_phone_agency" => true
           }) == ["transport à la demande"]

    # Does not crash when map is empty or some keys are not recognised
    assert Resource.find_tags_from_metadata(%{}) == []
    assert Resource.find_tags_from_metadata(%{"foo" => "bar"}) == []
  end

  test "get resource related geojson infos" do
    now = DateTime.now!("Etc/UTC")

    # we insert 3 resource history for a resource
    %{id: resource_id_1} = insert(:resource)
    insert_resource_history(resource_id_1, uuid1 = Ecto.UUID.generate(), now, -3600)
    insert_resource_history(resource_id_1, uuid2 = Ecto.UUID.generate(), now)
    insert_resource_history(resource_id_1, uuid3 = Ecto.UUID.generate(), now, -3601)

    # and one for another resource
    %{id: resource_id_2} = insert(:resource)
    insert_resource_history(resource_id_2, uuid4 = Ecto.UUID.generate(), now)

    # we insert 1 conversion for each resource history
    insert_data_conversion(uuid1, "url1", 10)
    insert_data_conversion(uuid2, "url2", 12)
    insert_data_conversion(uuid3, "url3", 10)
    insert_data_conversion(uuid4, "url4", 10)

    assert %{url: "url2", filesize: "12", resource_history_last_up_to_date_at: _} =
             Resource.get_related_geojson_info(resource_id_1)

    assert nil == Resource.get_related_geojson_info(resource_id_1 - 10)

    assert %{geojson: %{url: "url2", filesize: "12", resource_history_last_up_to_date_at: _}} =
             Resource.get_related_files(%Resource{id: resource_id_1})
  end

  defp insert_resource_history(resource_id, uuid, datetime, time_delta_seconds \\ 0) do
    insert(:resource_history, %{
      resource_id: resource_id,
      payload: %{uuid: uuid},
      inserted_at: DateTime.add(datetime, time_delta_seconds, :second)
    })
  end

  defp insert_data_conversion(uuid, permanent_url, filesize) do
    insert(:data_conversion, %{
      resource_history_uuid: uuid,
      convert_from: "GTFS",
      convert_to: "GeoJSON",
      payload: %{permanent_url: permanent_url, filesize: filesize}
    })
  end

  test "needs validation with a JSON Schema" do
    schema_name = "etalab/foo"
    resource = insert(:resource, %{schema_name: schema_name})

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{schema_name => %{}} end)

    assert {true, "schema is set"} == Resource.can_validate?(resource)
    assert {true, "schema is set and no previous validation"} == Resource.need_validate?(resource, false)
    assert {true, "schema is set and no previous validation"} == Resource.needs_validation(resource, false)
  end

  test "needs validation when schema is set but not in list" do
    resource = insert(:resource, %{schema_name: "foo"})

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 2, fn -> %{} end)

    assert {false, "schema is set"} == Resource.can_validate?(resource)
    assert {true, "schema is set and no previous validation"} == Resource.need_validate?(resource, false)
    assert {false, "schema is set"} == Resource.needs_validation(resource, false)
  end

  test "needs validation when schema is set and content hash is set" do
    schema_name = "etalab/foo"

    resource =
      insert(:resource, %{
        schema_name: schema_name,
        content_hash: "hash",
        url: "https://example.com/file",
        datagouv_id: "1"
      })

    Transport.Shared.Schemas.Mock
    |> expect(:transport_schemas, 4, fn -> %{schema_name => %{}} end)

    assert {true, "schema is set"} == Resource.can_validate?(resource)
    assert {true, "schema is set and no previous validation"} == Resource.need_validate?(resource, false)
    assert {true, "schema is set and no previous validation"} == Resource.needs_validation(resource, false)

    # Set the same content hash in the validation metadata
    resource =
      resource |> Resource.changeset(%{metadata: %{"validation" => %{"content_hash" => "hash"}}}) |> DB.Repo.update!()

    assert {false, "schema is set but content hash has not changed"} == Resource.needs_validation(resource, false)

    # Set the a different content hash in the validation metadata
    resource =
      resource |> Resource.changeset(%{metadata: %{"validation" => %{"content_hash" => "nope"}}}) |> DB.Repo.update!()

    assert {true, "schema is set and content hash has changed"} == Resource.needs_validation(resource, false)
  end

  describe "resource last content update time" do
    test "basic case" do
      %{id: resource_id} = insert(:resource)

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)}
      })

      assert expected_last_update_time == resource_id |> Resource.content_updated_at()
    end

    test "only one resource history, we don't know the resource last content update time" do
      %{id: resource_id} = insert(:resource, %{datagouv_id: datagouv_id = "datagouv_id"})

      insert(:resource_history, %{
        datagouv_id: datagouv_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      assert Resource.content_updated_at(resource_id) == nil
    end

    test "last content update time, download_datime not in payload" do
      %{id: resource_id} = insert(:resource, %{datagouv_id: datagouv_id = "datagouv_id"})
      insert(:resource_history, %{datagouv_id: datagouv_id, payload: %{}})

      assert Resource.content_updated_at(resource_id) == nil
    end

    test "last content update time, some download_datetime not in payload" do
      %{id: resource_id} = insert(:resource)
      insert(:resource_history, %{payload: %{}})

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: DateTime.utc_now() |> DateTime.add(-7200)}
      })

      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{download_datetime: expected_last_update_time = DateTime.utc_now() |> DateTime.add(-3600)}
      })

      assert expected_last_update_time == resource_id |> Resource.content_updated_at()
    end
  end

  test "download url" do
    # Files hosted on data.gouv.fr
    assert Resource.download_url(%Resource{
             filetype: "file",
             url: "https://demo-static.data.gouv.fr/resources/base-nationale-zfe/20220412-121638/voies.geojson",
             latest_url: latest_url = "https://demo.data.gouv.fr/fake_stable_url"
           }) == latest_url

    assert Resource.download_url(%Resource{
             filetype: "file",
             url: "https://static.data.gouv.fr/resources/base-nationale-zfe/20220412-121638/voies.geojson",
             latest_url: latest_url = "https://data.gouv.fr/fake_stable_url"
           }) == latest_url

    # Bison Futé folder
    assert Resource.download_url(%Resource{
             filetype: "remote",
             url: "http://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/QTV-DIR/",
             latest_url: latest_url = "https://data.gouv.fr/fake_stable_url"
           }) == latest_url

    # Bison Futé files
    assert Resource.download_url(%Resource{
             filetype: "remote",
             id: id = 1,
             url: "http://tipi.bison-fute.gouv.fr/bison-fute-ouvert/publicationsDIR/QTV-DIR/refDir.csv",
             latest_url: "https://data.gouv.fr/fake_stable_url"
           }) == resource_url(TransportWeb.Endpoint, :download, id)

    # File not hosted on data.gouv.fr
    assert Resource.download_url(%Resource{filetype: "file", url: url = "https://data.example.com/voies.geojson"}) ==
             url

    # Remote filetype / can direct download
    assert Resource.download_url(%Resource{filetype: "remote", url: url = "https://data.example.com/data"}) == url
    # http URL
    assert Resource.download_url(%Resource{id: id = 1, filetype: "remote", url: "http://data.example.com/data"}) ==
             resource_url(TransportWeb.Endpoint, :download, id)

    # file hosted on GitHub
    assert Resource.download_url(%Resource{
             id: id = 1,
             filetype: "remote",
             url:
               "https://raw.githubusercontent.com/etalab/transport-base-nationale-covoiturage/898dc67fb19fae2464c24a85a0557e8ccce18791/bnlc-.csv"
           }) == resource_url(TransportWeb.Endpoint, :download, id)
  end
end
