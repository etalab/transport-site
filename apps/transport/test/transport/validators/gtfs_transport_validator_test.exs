defmodule Transport.Validators.GtfsTransportValidatorTest do
  use ExUnit.Case, async: true
  import Mox
  import DB.Factory

  doctest Transport.Validators.GTFSTransport, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "the GTFS validator inserts expected data in DB" do
    %{id: resource_history_id} = insert(:resource_history)
    validation_content = %{"errors" => 2}
    data_vis_content = %{"data_vis" => "some data vis"}
    metadata_content = %{"m" => 1, "validator_version" => validator_version = "0.2.0"}

    Transport.DataVisualization.Mock
    |> expect(:validation_data_vis, 1, fn _ ->
      data_vis_content
    end)

    Shared.Validation.Validator.Mock
    |> expect(:validate_from_url, 1, fn _url ->
      {:ok, %{"validations" => validation_content, "metadata" => metadata_content}}
    end)

    Transport.Validators.GTFSTransport.validate_and_save(%DB.ResourceHistory{
      id: resource_history_id,
      payload: %{"permanent_url" => "url"}
    })

    assert %{
             id: validation_id,
             result: ^validation_content,
             data_vis: ^data_vis_content,
             resource_history_id: ^resource_history_id,
             validator_version: ^validator_version
           } = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: resource_history_id)

    assert %{metadata: ^metadata_content, resource_history_id: ^resource_history_id} =
             DB.ResourceMetadata |> DB.Repo.get_by!(multi_validation_id: validation_id)
  end
end
