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
    insert(:multi_validation, %{resource_history_id: rh2.id, validator: validator_name})
    # needs validation
    rh3 = insert(:resource_history, %{payload: %{"format" => "GTFS"}})
    insert(:multi_validation, %{resource_history_id: rh3.id, validator: "coucou"})

    rh4 = insert(:resource_history, %{payload: %{"format" => "GTFS"}})

    assert :ok =
             Transport.Jobs.ResourceHistoryValidationJob
             |> perform_job(%{"format" => "GTFS", "validator" => validator_string})

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh3.id, "validator" => validator}
    )

    assert_enqueued(
      worker: Transport.Jobs.ResourceHistoryValidationJob,
      args: %{"resource_history_id" => rh4.id, "validator" => validator}
    )

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
