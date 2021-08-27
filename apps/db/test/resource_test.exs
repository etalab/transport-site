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

  def validation_response do
    {:ok,
     %{
       "metadata" => %{
         "end_date" => "2022-07-06",
         "has_fares" => false,
         "has_shapes" => true,
         "issues_count" => %{},
         "lines_count" => 2,
         "modes" => ["bus"],
         "networks" => ["Réso"],
         "some_stops_need_phone_agency" => false,
         "some_stops_need_phone_driver" => false,
         "start_date" => "2021-07-07",
         "stop_areas_count" => 42,
         "stop_points_count" => 58
       },
       "validations" => %{}
     }}
  end

  test "validate and save a resource" do
    resource = insert(:resource, %{url: "url1", format: "GTFS"})

    DB.Resource.GtfsTransportValidator.Mock
    |> expect(:validate, 1, fn %Resource{url: url, format: "GTFS"} ->
      assert url == resource.url

      validation_response()
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
    DB.Resource.GtfsTransportValidator.Mock
    |> expect(:validate, 1, fn %Resource{url: url, format: "GTFS"} ->
      assert url |> String.contains?(resource.url)

      validation_response()
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
    DB.Resource.GtfsTransportValidator.Mock
    |> expect(:validate, 2, fn %Resource{url: url, format: "GTFS"} ->
      assert url |> String.contains?(resource.url)

      validation_response()
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
