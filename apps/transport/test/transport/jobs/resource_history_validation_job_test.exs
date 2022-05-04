defmodule Transport.Jobs.ResourceHistoryValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "validate all resource history, fixed format and validator" do
    validator = Transport.Validators.Dummy
    validator_string = validator |> to_string()
    validator_name = validator.validator_name()

    # bad format
    _rh1 = insert(:resource_history, %{payload: %{"format" => "NeTEx"}})
    # already validated
    rh2 = insert(:resource_history, %{payload: %{"format" => "GTFS"}})
    # needs validation
    rh3 = insert(:resource_history, %{payload: %{"format" => "GTFS"}})
    rh4 = insert(:resource_history, %{payload: %{"format" => "GTFS"}})

    insert(:multi_validation, %{resource_history_id: rh2.id, validator: validator_name})
    insert(:multi_validation, %{resource_history_id: rh3.id, validator: "coucou"})

    %Oban.Job{args: %{"format" => "GTFS", "validator" => validator_string}}
    |> Transport.Jobs.ResourceHistoryValidationJob.perform()

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh3.id, "validator" => validator}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh4.id, "validator" => validator}
    )
  end

  test "validate a resource history with one validator" do
    rh1 = insert(:resource_history)

    %Oban.Job{args: %{"resource_history_id" => rh1.id, "validator" => "Elixir.Transport.Validators.Dummy"}}
    |> Transport.Jobs.ResourceHistoryValidationJob.perform()

    # dummy validator sends a message for testing
    assert_received :validate!
  end

  test "validate all resource history" do
    Transport.ValidatorsSelection.Mock
    |> expect(:formats_and_validators, 1, fn ->
      %{
        "GTFS" => [Transport.Validators.GTFSTransport, Transport.Validators.Dummy],
        "SIRI" => [Transport.Validators.Dummy]
      }
    end)

    Transport.Jobs.ResourceHistoryValidationJob.perform(%Oban.Job{})

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"format" => "GTFS", "validator" => Transport.Validators.GTFSTransport}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"format" => "GTFS", "validator" => Transport.Validators.Dummy}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"format" => "SIRI", "validator" => Transport.Validators.Dummy}
    )
  end

  test "all validations for one resource history" do
    %{id: resource_history_id} = insert(:resource_history, %{payload: %{"format" => "GTFS"}})

    Transport.ValidatorsSelection.Mock
    |> expect(:validators, 1, fn "GTFS" ->
      [Transport.Validators.Dummy, Transport.Validators.Dummy]
    end)

    %Oban.Job{args: %{"resource_history_id" => resource_history_id}}
    |> Transport.Jobs.ResourceHistoryValidationJob.perform()

    # validation has been launched twice
    assert_received :validate!
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
