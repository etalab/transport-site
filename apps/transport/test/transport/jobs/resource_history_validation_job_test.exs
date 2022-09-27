defmodule Transport.Jobs.ResourceHistoryValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def insert_data(validator_name) do
    rh = insert(:resource)

    # bad format
    _rh1 = insert(:resource_history, %{payload: %{"format" => "NeTEx"}})
    # already validated
    rh2 = insert(:resource_history, %{payload: %{"format" => "GTFS"}})
    insert(:multi_validation, %{resource_history_id: rh2.id, validator: validator_name})
    # needs validation
    rh3 =
      insert(:resource_history, %{payload: %{"format" => "GTFS"}, resource_id: rh.id, inserted_at: DateTime.utc_now()})

    insert(:multi_validation, %{resource_history_id: rh3.id, validator: "coucou"})

    rh4 =
      insert(:resource_history, %{
        payload: %{"format" => "GTFS"},
        resource_id: rh.id,
        inserted_at: DateTime.utc_now() |> DateTime.add(-600)
      })

    {rh2, rh3, rh4}
  end

  test "validate all resource history, fixed format and validator" do
    validator = Transport.Validators.Dummy
    validator_string = validator |> to_string()
    validator_name = validator.validator_name()

    {_rh2, rh3, rh4} = insert_data(validator_name)

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"format" => "GTFS", "validator" => validator_string})

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh3.id, "validator" => validator, "force_validation" => false}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh4.id, "validator" => validator, "force_validation" => false}
    )

    assert 2 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryValidationJob))
  end

  test "validate all resource history, fixed format and validator - forced mode" do
    validator = Transport.Validators.Dummy
    validator_string = validator |> to_string()
    validator_name = validator.validator_name()

    {rh2, rh3, rh4} = insert_data(validator_name)

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"format" => "GTFS", "validator" => validator_string, "force_validation" => true})

    # rh2 is validated, because validation is forced
    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh2.id, "validator" => validator, "force_validation" => true}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh3.id, "validator" => validator, "force_validation" => true}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh4.id, "validator" => validator, "force_validation" => true}
    )

    assert 3 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryValidationJob))
  end

  test "validate only latest resource history, fixed format and validator - forced mode" do
    validator = Transport.Validators.Dummy
    validator_string = validator |> to_string()
    validator_name = validator.validator_name()

    {rh2, rh3, _rh4} = insert_data(validator_name)

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{
               "format" => "GTFS",
               "validator" => validator_string,
               "force_validation" => true,
               "only_latest_resource_history" => true
             })

    # rh2 is validated, because validation is forced
    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh2.id, "validator" => validator, "force_validation" => true}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh3.id, "validator" => validator, "force_validation" => true}
    )

    # rh4 is not enqueued, because rh3 is the latest resource history for that resource

    assert 2 == Enum.count(all_enqueued(worker: Transport.Jobs.ResourceHistoryValidationJob))
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
    assert {:discard, msg} =
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
