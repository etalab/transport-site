defmodule DB.MultiValidationTest do
  use ExUnit.Case, async: true
  doctest DB.MultiValidation, import: true
  import DB.Factory
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "already validated" do
    %{id: resource_history_id} = resource_history = insert(:resource_history)

    refute DB.MultiValidation.already_validated?(resource_history, Transport.Validators.Dummy)

    # wrong validator name
    insert(:multi_validation, %{validator: "random validator", resource_history_id: resource_history_id})
    refute DB.MultiValidation.already_validated?(resource_history, Transport.Validators.Dummy)

    insert(:multi_validation, %{
      validator: Transport.Validators.Dummy.validator_name(),
      resource_history_id: resource_history_id
    })

    assert DB.MultiValidation.already_validated?(resource_history, Transport.Validators.Dummy)
  end

  describe "get latest associated multi validation" do
    test "get resource latest validation" do
      now = DateTime.utc_now()
      before60 = DateTime.utc_now() |> DateTime.add(-60)
      before90 = DateTime.utc_now() |> DateTime.add(-90)

      validator = Transport.Validators.GTFSTransport
      validator_name = validator.validator_name()

      # one dataset
      %{id: dataset_id} = insert(:dataset)

      # one resource
      %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id})

      # one resource history with some validations
      %{id: resource_history_id_latest} = insert(:resource_history, %{resource_id: resource_id, inserted_at: now})

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
      %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id, inserted_at: before60})

      # with a very recent validation (it's a trap!)
      insert(:multi_validation, %{
        resource_history_id: resource_history_id,
        validator: validator_name,
        validation_timestamp: now
      })

      assert %{id: ^mv_id, resource_history_id: ^resource_history_id_latest} =
               DB.MultiValidation.resource_latest_validation(resource_id, validator)

      dataset_validations = DB.MultiValidation.dataset_latest_validation(dataset_id, [validator])

      assert [%{id: ^mv_id, resource_history_id: ^resource_history_id_latest}] =
               dataset_validations |> Map.get(resource_id)
    end

    test "resource_latest_validation scopes by resource_id" do
      now = DateTime.utc_now()
      before60 = DateTime.utc_now() |> DateTime.add(-60)

      validator = Transport.Validators.GTFSTransport
      validator_name = validator.validator_name()

      %{id: dataset_id} = insert(:dataset)
      %{id: resource_id1} = insert(:resource, %{dataset_id: dataset_id})
      %{id: resource_id2} = insert(:resource, %{dataset_id: dataset_id})

      # one resource history with a validation for resource_id1
      %{id: resource_history_id1} = insert(:resource_history, %{resource_id: resource_id1, inserted_at: before60})

      %{id: mv_id1} =
        insert(:multi_validation, %{
          resource_history_id: resource_history_id1,
          validator: validator_name,
          validation_timestamp: before60
        })

      # resource history and recent validation for resource_id2
      %{id: resource_history_id2} = insert(:resource_history, %{resource_id: resource_id2, inserted_at: now})

      %{id: mv_id2} =
        insert(:multi_validation, %{
          resource_history_id: resource_history_id2,
          validator: validator_name,
          validation_timestamp: now
        })

      assert %{id: ^mv_id1, resource_history_id: ^resource_history_id1} =
               DB.MultiValidation.resource_latest_validation(resource_id1, validator)

      # Making sure dataset_latest_validation works as well
      dataset_validations = DB.MultiValidation.dataset_latest_validation(dataset_id, [validator])

      assert [%{id: ^mv_id1, resource_history_id: ^resource_history_id1}] = dataset_validations |> Map.get(resource_id1)
      assert [%{id: ^mv_id2, resource_history_id: ^resource_history_id2}] = dataset_validations |> Map.get(resource_id2)
    end

    test "no resource latest validation, resource alone" do
      validator = Transport.Validators.GTFSTransport
      %{id: dataset_id} = insert(:dataset)
      %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id})

      assert nil == DB.MultiValidation.resource_latest_validation(resource_id, validator)

      dataset_validations = DB.MultiValidation.dataset_latest_validation(dataset_id, [validator])
      assert [nil] == dataset_validations |> Map.get(resource_id, "nothing")
    end

    test "no resource latest validation, resource + resource_history" do
      validator = Transport.Validators.GTFSTransport
      %{id: dataset_id} = insert(:dataset)
      %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id})
      insert(:resource_history, %{resource_id: resource_id})

      assert nil == DB.MultiValidation.resource_latest_validation(resource_id, validator)

      dataset_validations = DB.MultiValidation.dataset_latest_validation(dataset_id, [validator])
      assert [nil] == dataset_validations |> Map.get(resource_id, "nothing")
    end

    test "no resource latest validation with specified validator" do
      validator = Transport.Validators.GTFSTransport
      %{id: dataset_id} = insert(:dataset)
      %{id: resource_id} = insert(:resource, %{dataset_id: dataset_id})
      %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id})

      insert(:multi_validation, %{
        resource_history_id: resource_history_id,
        validator: "other_validator_name"
      })

      assert nil == DB.MultiValidation.resource_latest_validation(resource_id, validator)

      dataset_validations = DB.MultiValidation.dataset_latest_validation(dataset_id, [validator])
      assert [nil] == dataset_validations |> Map.get(resource_id, "nothing")
    end

    test "dataset validations, multiple resources and validators" do
      validator_1 = Transport.Validators.GTFSTransport
      validator_1_name = validator_1.validator_name()
      validator_2 = Transport.Validators.Dummy
      validator_2_name = validator_2.validator_name()

      %{id: dataset_id} = insert(:dataset)

      %{id: resource_id_1} = insert(:resource, %{dataset_id: dataset_id})
      %{id: resource_id_2} = insert(:resource, %{dataset_id: dataset_id})
      %{id: resource_id_3} = insert(:resource, %{dataset_id: dataset_id})

      %{id: resource_history_id_1} = insert(:resource_history, %{resource_id: resource_id_1})
      %{id: resource_history_id_2} = insert(:resource_history, %{resource_id: resource_id_2})

      insert(:multi_validation, %{
        resource_history_id: resource_history_id_1,
        validator: validator_1.validator_name()
      })

      insert(:multi_validation, %{
        resource_history_id: resource_history_id_1,
        validator: validator_2.validator_name()
      })

      insert(:multi_validation, %{
        resource_history_id: resource_history_id_2,
        validator: validator_1.validator_name()
      })

      validations = DB.MultiValidation.dataset_latest_validation(dataset_id, [validator_1, validator_2])

      resource_1_validations = validations |> Map.get(resource_id_1) |> Enum.sort_by(fn %{id: id} -> id end)

      assert [
               %{resource_history_id: ^resource_history_id_1, validator: ^validator_1_name},
               %{resource_history_id: ^resource_history_id_1, validator: ^validator_2_name}
             ] = resource_1_validations

      assert [%{resource_history_id: ^resource_history_id_2, validator: ^validator_1_name}] =
               validations |> Map.get(resource_id_2)

      assert [nil] = validations |> Map.get(resource_id_3)
    end

    test "dataset_latest_validation with ResourceMetadata joined by multi_validation_id" do
      validator_1 = Transport.Validators.GTFSTransport

      %{id: dataset_id} = insert(:dataset)
      %{id: resource_id_1} = insert(:resource, %{dataset_id: dataset_id})
      %{id: resource_history_id_1} = insert(:resource_history, %{resource_id: resource_id_1})

      %{id: multi_validation_id} =
        insert(:multi_validation, %{
          resource_history_id: resource_history_id_1,
          validator: validator_1.validator_name(),
          metadata: %DB.ResourceMetadata{metadata: %{"foo" => "bar"}}
        })

      validations = DB.MultiValidation.dataset_latest_validation(dataset_id, [validator_1])

      resource_1_validations = validations |> Map.get(resource_id_1)

      assert Enum.count(resource_1_validations) == 1
      latest_multi_validation = hd(resource_1_validations)

      assert %{metadata: %{"foo" => "bar"}, multi_validation_id: ^multi_validation_id} =
               latest_multi_validation.metadata

      assert DB.MultiValidation.get_metadata_info(latest_multi_validation, "foo") == "bar"
      assert is_nil(DB.MultiValidation.get_metadata_info(latest_multi_validation, "baz"))
    end
  end

  test "latest resource validation (no resource history)" do
    # when validating a GTFS-RT, the resource is validated but there is no resource_history.
    validator = Transport.Validators.GTFSRT
    validator_name = validator.validator_name()

    dataset = insert(:dataset)

    resource = insert(:resource, dataset_id: dataset.id)
    other_resource = insert(:resource, dataset_id: dataset.id)

    # old
    insert(:multi_validation,
      resource_id: resource.id,
      validation_timestamp: DateTime.utc_now() |> DateTime.add(-120),
      validator: validator_name
    )

    # bad validator
    insert(:multi_validation,
      resource_id: resource.id,
      validation_timestamp: DateTime.utc_now() |> DateTime.add(-30),
      validator: "xxx"
    )

    # good
    %{id: mv_id} =
      insert(:multi_validation,
        resource_id: resource.id,
        validation_timestamp: DateTime.utc_now() |> DateTime.add(-60),
        validator: validator_name
      )

    # other resource
    %{id: other_mv_id} =
      insert(:multi_validation,
        resource_id: other_resource.id,
        validation_timestamp: DateTime.utc_now(),
        validator: validator_name
      )

    assert %{id: ^mv_id} = DB.MultiValidation.resource_latest_validation(resource.id, validator)

    validations = DB.MultiValidation.dataset_latest_validation(dataset.id, [validator])

    assert [%{id: ^mv_id}] = validations |> Map.get(resource.id)
    assert [%{id: ^other_mv_id}] = validations |> Map.get(other_resource.id)
  end

  test "composable join query for latest validation" do
    resource_history = insert(:resource_history)
    insert(:resource_history)

    mv1 =
      insert(:multi_validation,
        resource_history_id: resource_history.id,
        validator: "v1",
        inserted_at: DateTime.utc_now()
      )

    insert(:multi_validation,
      resource_history_id: resource_history.id,
      validator: "v2",
      inserted_at: DateTime.utc_now() |> DateTime.add(-100)
    )

    mv2 =
      insert(:multi_validation,
        resource_history_id: resource_history.id,
        validator: "v2",
        inserted_at: DateTime.utc_now() |> DateTime.add(-50)
      )

    assert mv2 ==
             DB.ResourceHistory.base_query()
             |> where([resource_history: rh], rh.id == ^resource_history.id)
             |> DB.MultiValidation.join_resource_history_with_latest_validation("v2")
             |> select([multi_validation: mv], mv)
             |> DB.Repo.one!()

    assert mv1 ==
             DB.ResourceHistory.base_query()
             |> where([resource_history: rh], rh.id == ^resource_history.id)
             |> DB.MultiValidation.join_resource_history_with_latest_validation(["v1", "v2"])
             |> select([multi_validation: mv], mv)
             |> DB.Repo.one!()
  end
end
