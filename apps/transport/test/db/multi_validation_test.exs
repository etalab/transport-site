defmodule DB.MultiValidationTest do
  use ExUnit.Case, async: true
  doctest DB.MultiValidation
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "already validated" do
    %{id: resource_history_id} = resource_history = insert(:resource_history)

    refute DB.MultiValidation.already_validated?(resource_history, Transport.Validators.Dummy)

    # wrong validator name
    insert(:multi_validation, %{validator: "coucou", resource_history_id: resource_history_id})
    refute DB.MultiValidation.already_validated?(resource_history, Transport.Validators.Dummy)

    insert(:multi_validation, %{
      validator: Transport.Validators.Dummy.validator_name(),
      resource_history_id: resource_history_id
    })

    assert DB.MultiValidation.already_validated?(resource_history, Transport.Validators.Dummy)
  end
end
