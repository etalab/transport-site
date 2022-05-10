defmodule DB.MultiValidationTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "get resource latest validation" do
    now = DateTime.utc_now()
    before60 = DateTime.utc_now() |> DateTime.add(-60)
    before90 = DateTime.utc_now() |> DateTime.add(-90)

    validator = Transport.Validators.GTFSTransport
    validator_name = validator.validator_name()

    # one resource
    %{id: resource_id} = insert(:resource, %{datagouv_id: datagouv_id = "datagouv_id"})

    # one resource history with some validations
    %{id: resource_history_id_latest} = insert(:resource_history, %{datagouv_id: datagouv_id, inserted_at: now})

    insert(:multi_validation, %{
      resource_history_id: resource_history_id_latest,
      validator: "other",
      validation_timestamp: now
    })

    insert(:multi_validation, %{
      resource_history_id: resource_history_id_latest,
      validator: validator_name,
      validation_timestamp: before90
    })

    %{id: mv_id} =
      insert(:multi_validation, %{
        resource_history_id: resource_history_id_latest,
        validator: validator_name,
        validation_timestamp: before60
      })

    # a second older resource history
    %{id: resource_history_id} = insert(:resource_history, %{datagouv_id: datagouv_id, inserted_at: before60})

    # with a very recent validation (it's a trap!)
    insert(:multi_validation, %{
      resource_history_id: resource_history_id,
      validator: validator_name,
      validation_timestamp: now
    })

    assert %{id: ^mv_id, resource_history_id: ^resource_history_id_latest} =
             DB.MultiValidation.resource_latest_validation(resource_id, validator)
  end
end
