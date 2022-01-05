defmodule DB.ResourceTest do
  use ExUnit.Case, async: true
  alias Validation.Validator.Mock, as: ValidatorMock
  alias DB.{LogsValidation, Repo, Resource, Validation}
  import Mox
  import DB.Factory
  import Ecto.Query

  doctest Resource

  setup do
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
    |> expect(:compute_feed_metadata, fn _resource, _cors_base_url -> %{"foo" => "bar"} end)

    assert {true, "gbfs can be validated"} == Resource.can_validate?(resource)
    assert Resource.validate_and_save(resource, false) == {:ok, nil}
    assert %{metadata: %{"foo" => "bar"}} = Repo.get(Resource, resource.id)
  end

  test "validate and save a resource with a JSON Schema" do
    url = "https://example.com/file"
    schema_name = "etalab/foo"

    resource = insert(:resource, %{url: url, schema_name: schema_name, metadata: %{"bar" => "baz"}})

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 2, fn type ->
      assert type == "jsonschema"
      %{schema_name => %{}}
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
    assert Resource.need_validate?(resource, false)
    assert Resource.validate_and_save(resource, false) == {:ok, nil}
    assert %{metadata: %{"bar" => "baz", "validation" => %{"foo" => "bar"}}} = Repo.get(Resource, resource.id)
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

  test "needs validation with a JSON Schema" do
    schema_name = "etalab/foo"
    resource = insert(:resource, %{schema_name: schema_name})

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 2, fn type ->
      assert type == "jsonschema"
      %{schema_name => %{}}
    end)

    assert {true, "schema is set"} == Resource.can_validate?(resource)
    assert Resource.need_validate?(resource, false)
    assert {true, "schema is set"} == Resource.needs_validation(resource, false)
  end

  test "needs validation when schema is set but not in list" do
    resource = insert(:resource, %{schema_name: "foo"})

    Transport.Shared.Schemas.Mock
    |> expect(:schemas_by_type, 2, fn type ->
      assert type == "jsonschema"
      %{}
    end)

    assert {false, "schema is set"} == Resource.can_validate?(resource)
    assert Resource.need_validate?(resource, false)
    assert {false, "schema is set"} == Resource.needs_validation(resource, false)
  end
end
