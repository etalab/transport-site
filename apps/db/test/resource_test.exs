defmodule DB.ResourceTest do
  use ExUnit.Case, async: true
  alias DB.{LogsValidation, Repo, Resource, Validation}
  import Mox
  import DB.Factory
  import Ecto.Query

  doctest Resource

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "validate and save a resource" do
    resource = insert(:resource, %{url: "url1", format: "GTFS"})

    Transport.HTTPoison.Mock
    |> expect(:get, 1, fn url, [], _ ->
      assert url |> String.contains?(resource.url)

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           "{\"metadata\":{\"start_date\":\"2021-07-08\",\"end_date\":\"2021-10-24\",\"stop_areas_count\":588,\"stop_points_count\":1016,\"lines_count\":126,\"networks\":[\"Sté de Transport de l'Agglomération Nazairienne\"],\"modes\":[\"bus\"],\"issues_count\":{\"ExcessiveSpeed\":2,\"NullDuration\":10,\"DuplicateStops\":43},\"has_fares\":false,\"has_shapes\":true,\"some_stops_need_phone_agency\":false,\"some_stops_need_phone_driver\":false},\"validations\":{\"ExcessiveSpeed\":[{\"severity\":\"Information\",\"issue_type\":\"ExcessiveSpeed\",\"object_id\":\"22226\",\"object_type\":\"Stop\",\"object_name\":\"FossedeRotz\",\"related_objects\":[{\"id\":\"21994\",\"object_type\":\"Stop\",\"name\":\"FosseBlanc\"},{\"id\":\"118\",\"object_type\":\"Route\",\"name\":\"301\"}],\"details\":\"computed speed between the stops is 525.76 km/h (17525 m travelled in 120 seconds)\"}]}}"
       }}
    end)

    assert Resource.validate_and_save(resource, false) == {:ok, nil}

    # a validation is saved in the DB
    validations = Validation |> where([v], v.resource_id == ^resource.id) |> Repo.all()
    assert length(validations) == 1

    # a log of the validation is saved as well
    [log_validation] = LogsValidation |> where([l], l.resource_id == ^resource.id) |> Repo.all()
    assert log_validation.skipped_reason == "no previous validation"
  end

  test "validation is skipped if previous validation is still valid" do
    resource = insert(:resource, %{url: "url1", format: "GTFS", content_hash: "sha256_hash"})

    # we expect the validator the be called only once, as the second validation
    # should be skipped
    Transport.HTTPoison.Mock
    |> expect(:get, 1, fn url, [], _ ->
      assert url |> String.contains?(resource.url)

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           "{\"metadata\":{\"start_date\":\"2021-07-08\",\"end_date\":\"2021-10-24\",\"stop_areas_count\":588,\"stop_points_count\":1016,\"lines_count\":126,\"networks\":[\"Sté de Transport de l'Agglomération Nazairienne\"],\"modes\":[\"bus\"],\"issues_count\":{\"ExcessiveSpeed\":2,\"NullDuration\":10,\"DuplicateStops\":43},\"has_fares\":false,\"has_shapes\":true,\"some_stops_need_phone_agency\":false,\"some_stops_need_phone_driver\":false},\"validations\":{\"ExcessiveSpeed\":[{\"severity\":\"Information\",\"issue_type\":\"ExcessiveSpeed\",\"object_id\":\"22226\",\"object_type\":\"Stop\",\"object_name\":\"FossedeRotz\",\"related_objects\":[{\"id\":\"21994\",\"object_type\":\"Stop\",\"name\":\"FosseBlanc\"},{\"id\":\"118\",\"object_type\":\"Route\",\"name\":\"301\"}],\"details\":\"computed speed between the stops is 525.76 km/h (17525 m travelled in 120 seconds)\"}]}}"
       }}
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
    Transport.HTTPoison.Mock
    |> expect(:get, 2, fn url, [], _ ->
      assert url |> String.contains?(resource.url)

      {:ok,
       %HTTPoison.Response{
         status_code: 200,
         body:
           "{\"metadata\":{\"start_date\":\"2021-07-08\",\"end_date\":\"2021-10-24\",\"stop_areas_count\":588,\"stop_points_count\":1016,\"lines_count\":126,\"networks\":[\"Sté de Transport de l'Agglomération Nazairienne\"],\"modes\":[\"bus\"],\"issues_count\":{\"ExcessiveSpeed\":2,\"NullDuration\":10,\"DuplicateStops\":43},\"has_fares\":false,\"has_shapes\":true,\"some_stops_need_phone_agency\":false,\"some_stops_need_phone_driver\":false},\"validations\":{\"ExcessiveSpeed\":[{\"severity\":\"Information\",\"issue_type\":\"ExcessiveSpeed\",\"object_id\":\"22226\",\"object_type\":\"Stop\",\"object_name\":\"FossedeRotz\",\"related_objects\":[{\"id\":\"21994\",\"object_type\":\"Stop\",\"name\":\"FosseBlanc\"},{\"id\":\"118\",\"object_type\":\"Route\",\"name\":\"301\"}],\"details\":\"computed speed between the stops is 525.76 km/h (17525 m travelled in 120 seconds)\"}]}}"
       }}
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
end
