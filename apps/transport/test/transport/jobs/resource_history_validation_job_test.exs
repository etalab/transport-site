defmodule Transport.Jobs.ResourceHistoryValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @formats ["GTFS", "NeTEx"]

  def insert_data(validator_name, format) do
    rh = insert(:resource)

    # already validated
    already_validated = insert(:resource_history, %{payload: %{"format" => format}})
    insert(:multi_validation, %{resource_history_id: already_validated.id, validator: validator_name})

    # pending validation
    pending1 =
      insert(:resource_history, %{payload: %{"format" => format}, resource_id: rh.id, inserted_at: DateTime.utc_now()})

    insert(:multi_validation, %{resource_history_id: pending1.id, validator: "coucou"})

    pending2 =
      insert(:resource_history, %{
        payload: %{"format" => format},
        resource_id: rh.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-600)
      })

    %{already_validated: already_validated, pending: [pending1, pending2]}
  end

  for format <- @formats do
    describe format do
      @describetag format: format

      test "validate all resource history, fixed format and validator", %{format: format} do
        validator = Transport.Validators.Dummy
        validator_string = validator |> to_string()
        validator_name = validator.validator_name()

        %{pending: [pending1, pending2]} = insert_data(validator_name, format)

        assert :ok =
                 Transport.Jobs.ResourceHistoryValidationJob
                 |> perform_job(%{"format" => format, "validator" => validator_string})

        assert_enqueued(
          worker: Transport.Jobs.ResourceHistoryValidationJob,
          args: %{"resource_history_id" => pending1.id, "validator" => validator, "force_validation" => false}
        )

        assert_enqueued(
          worker: Transport.Jobs.ResourceHistoryValidationJob,
          args: %{"resource_history_id" => pending2.id, "validator" => validator, "force_validation" => false}
        )

        assert 2 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryValidationJob))
      end

      test "validate all resource history, fixed format and validator - forced mode", %{format: format} do
        validator = Transport.Validators.Dummy
        validator_string = validator |> to_string()
        validator_name = validator.validator_name()

        %{already_validated: already_validated, pending: [pending1, pending2]} = insert_data(validator_name, format)

        assert :ok =
                 Transport.Jobs.ResourceHistoryValidationJob
                 |> perform_job(%{"format" => format, "validator" => validator_string, "force_validation" => true})

        # already_validated is validated, because validation is forced
        assert_enqueued(
          worker: Transport.Jobs.ResourceHistoryValidationJob,
          args: %{"resource_history_id" => already_validated.id, "validator" => validator, "force_validation" => true}
        )

        assert_enqueued(
          worker: Transport.Jobs.ResourceHistoryValidationJob,
          args: %{"resource_history_id" => pending1.id, "validator" => validator, "force_validation" => true}
        )

        assert_enqueued(
          worker: Transport.Jobs.ResourceHistoryValidationJob,
          args: %{"resource_history_id" => pending2.id, "validator" => validator, "force_validation" => true}
        )

        assert 3 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryValidationJob))
      end

      test "validate only latest resource history, fixed format and validator - forced mode", %{format: format} do
        validator = Transport.Validators.Dummy
        validator_string = validator |> to_string()
        validator_name = validator.validator_name()

        %{already_validated: already_validated, pending: [pending1, _pending2]} = insert_data(validator_name, format)

        assert :ok =
                 Transport.Jobs.ResourceHistoryValidationJob
                 |> perform_job(%{
                   "format" => format,
                   "validator" => validator_string,
                   "force_validation" => true,
                   "only_latest_resource_history" => true
                 })

        # already_validated is validated, because validation is forced
        assert_enqueued(
          worker: Transport.Jobs.ResourceHistoryValidationJob,
          args: %{"resource_history_id" => already_validated.id, "validator" => validator, "force_validation" => true}
        )

        assert_enqueued(
          worker: Transport.Jobs.ResourceHistoryValidationJob,
          args: %{"resource_history_id" => pending1.id, "validator" => validator, "force_validation" => true}
        )

        # pending2 is not enqueued, because pending1 is the latest resource history for that resource

        assert 2 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryValidationJob))
      end
    end
  end

  test "validate a resource history with one validator" do
    rh1 = insert(:resource_history)

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{
               "resource_history_id" => rh1.id,
               "validator" => Transport.Validators.Dummy |> to_string()
             })

    # dummy validator sends a message for testing
    assert_received :validate!
  end

  test "GTFS-Flex is validated with the MobilityData one" do
    permanent_url = "https://example.com/gtfs"
    job_id = Ecto.UUID.generate()
    report_html_url = "https://example.com/#{job_id}/report.html"

    rh =
      insert(:resource_history,
        payload: %{
          "format" => "GTFS",
          "filenames" => ["locations.geojson", "stops.txt"],
          "permanent_url" => permanent_url
        }
      )

    assert DB.ResourceHistory.gtfs_flex?(rh)

    Transport.ValidatorsSelection.Mock
    |> expect(:validators, 1, fn ^rh ->
      [Transport.Validators.MobilityDataGTFSValidator]
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :create_a_validation, fn ^permanent_url ->
      job_id
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :get_a_validation, fn ^job_id ->
      notices = [
        %{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2, "sampleNotices" => ["foo", "bar"]}
      ]

      report = %{"summary" => %{"validatorVersion" => "4.2.0"}, "notices" => notices}
      {:successful, report}
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :report_html_url, fn ^job_id ->
      report_html_url
    end)

    assert :ok ==
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"resource_history_id" => rh.id})
  end

  test "all validations for one resource history" do
    %{id: resource_history_id} = resource_history = insert(:resource_history, %{payload: %{"format" => "GTFS"}})

    Transport.ValidatorsSelection.Mock
    |> expect(:validators, 1, fn ^resource_history ->
      [Transport.Validators.Dummy, Transport.Validators.Dummy]
    end)

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"resource_history_id" => resource_history_id})

    # validation has been launched twice
    assert_received :validate!
    assert_received :validate!
  end

  test "single resource history validation" do
    rh = insert(:resource_history)
    validator = Transport.Validators.Dummy
    validator_string = validator |> to_string()
    validator_name = validator.validator_name()

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"resource_history_id" => rh.id, "validator" => validator_string})

    # validation is performed
    assert_received :validate!

    # we insert manually a mv
    mv = insert(:multi_validation, resource_history_id: rh.id, validator: validator_name)
    md = insert(:resource_metadata, multi_validation_id: mv.id)

    # validation is skipped
    assert {:cancel, msg} =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"resource_history_id" => rh.id, "validator" => validator_string})

    assert msg =~ "already validated"

    # we force the validation
    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{
               "resource_history_id" => rh.id,
               "validator" => validator_string,
               "force_validation" => true
             })

    # existing validation & metadata have been deleted
    assert is_nil(DB.Repo.reload(mv))
    assert is_nil(DB.Repo.reload(md))

    # validation is called
    assert_received :validate!
  end

  test "single resource history validation, all validators" do
    rh = insert(:resource_history)
    validator = Transport.Validators.Dummy

    Transport.ValidatorsSelection.Mock
    |> expect(:validators, 3, fn ^rh ->
      [validator]
    end)

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"resource_history_id" => rh.id})

    # validation is performed
    assert_received :validate!

    # we insert manually a mv
    mv = insert(:multi_validation, resource_history_id: rh.id, validator: validator.validator_name())
    md = insert(:resource_metadata, multi_validation_id: mv.id)

    # validation is skipped
    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"resource_history_id" => rh.id})

    refute_receive :validate!, 50

    # we force the validation
    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{
               "resource_history_id" => rh.id,
               "force_validation" => true
             })

    # existing validation & metadata have been deleted
    assert is_nil(DB.Repo.reload(mv))
    assert is_nil(DB.Repo.reload(md))

    # validation is called
    assert_received :validate!
  end

  # wait for https://github.com/sorentwo/oban/issues/704 response
  # test "job uniqueness for a resource_history validation" do
  #   %{"resource_history_id" => 1, "validator" => "Elixir.Transport.Validators.Dummy"}
  #   |> Transport.Jobs.ResourceHistoryValidationJob.new()
  #   |> Oban.insert()

  #   %{"resource_history_id" => 1, "validator" => "Elixir.Transport.Validators.Dummy"}
  #   |> Transport.Jobs.ResourceHistoryValidationJob.new()
  #   |> Oban.insert()

  #   %{resource_history_id: 2, validator: "Elixir.Transport.Validators.Dummy"}
  #   |> Transport.Jobs.ResourceHistoryValidationJob.new()
  #   |> Oban.insert()

  #   %{}
  #   |> Transport.Jobs.ResourceHistoryValidationJob.new()
  #   |> Oban.insert()

  #   %{}
  #   |> Transport.Jobs.ResourceHistoryValidationJob.new()
  #   |> Oban.insert()

  #   assert jobs = all_enqueued()
  #   assert 2 == length(jobs)
  # end
end
