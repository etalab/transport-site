defmodule DB.ResourceMetadataTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "find validations with up to date gtfs resources" do
    validation_1 = insert(:multi_validation)
    validation_2 = insert(:multi_validation)

    insert(:resource_metadata,
      multi_validation_id: validation_1.id,
      metadata: %{"start_date" => Date.utc_today() |> Date.add(-3), "end_date" => Date.utc_today() |> Date.add(3)}
    )

    insert(:resource_metadata,
      multi_validation_id: validation_2.id,
      metadata: %{"start_date" => Date.utc_today() |> Date.add(-3), "end_date" => Date.utc_today() |> Date.add(-2)}
    )

    assert [validation_1] ==
             DB.MultiValidation.base_query()
             |> DB.ResourceMetadata.join_validation_with_metadata()
             |> DB.ResourceMetadata.where_gtfs_up_to_date()
             |> DB.Repo.all()
  end
end
