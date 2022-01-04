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

    assert Resource.validate_and_save(resource, false) == {:ok, nil}
    assert %{metadata: %{"foo" => "bar"}} = Repo.get(Resource, resource.id)
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

  test "get resource related geojson infos" do
    now = DateTime.now!("Etc/UTC")

    # we insert 3 resource history for datagouv_id_1
    insert_resouce_history("datagouv_id_1", uuid1 = Ecto.UUID.generate(), now, -3600)
    insert_resouce_history("datagouv_id_1", uuid2 = Ecto.UUID.generate(), now)
    insert_resouce_history("datagouv_id_1", uuid3 = Ecto.UUID.generate(), now, -3601)

    # and one for datagouv_id_2
    insert_resouce_history("datagouv_id_2", uuid4 = Ecto.UUID.generate(), now)

    # we insert 1 conversion for each resource history
    insert_data_conversion(uuid1, "url1", 10)
    insert_data_conversion(uuid2, "url2", 12)
    insert_data_conversion(uuid3, "url3", 10)
    insert_data_conversion(uuid4, "url4", 10)

    assert %{url: "url2", filesize: "12", resource_history_last_up_to_date_at: _} =
             DB.Resource.get_related_geojson_info("datagouv_id_1")

    assert nil == DB.Resource.get_related_geojson_info("other_id")

    assert %{geojson: %{url: "url2", filesize: "12", resource_history_last_up_to_date_at: _}} =
             DB.Resource.get_related_files(%DB.Resource{datagouv_id: "datagouv_id_1"})
  end

  defp insert_resouce_history(datagouv_id, uuid, datetime, time_delta_seconds \\ 0) do
    insert(:resource_history, %{
      datagouv_id: datagouv_id,
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
end
