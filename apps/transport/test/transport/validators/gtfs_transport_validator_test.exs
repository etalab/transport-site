defmodule Transport.Validators.GtfsTransportValidatorTest do
  use ExUnit.Case, async: true
  import Mox
  import DB.Factory
  alias Transport.Validators.GTFSTransport

  doctest Transport.Validators.GTFSTransport, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "the GTFS validator inserts expected data in DB" do
    %{id: resource_history_id} = insert(:resource_history)

    validation_content = %{
      "NullDuration" => [%{"severity" => "Information"}],
      "MissingCoordinates" => [%{"severity" => "Warning"}]
    }

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
             validator_version: ^validator_version,
             max_error: "Warning"
           } = DB.MultiValidation |> DB.Repo.get_by!(resource_history_id: resource_history_id)

    assert %{metadata: ^metadata_content, resource_history_id: ^resource_history_id} =
             DB.ResourceMetadata |> DB.Repo.get_by!(multi_validation_id: validation_id)
  end

  test "find_tags_from_metadata" do
    # Can detect all available tags
    assert ["transport à la demande"] ==
             GTFSTransport.find_tags_from_metadata(%{"some_stops_need_phone_agency" => true})

    assert ["transport à la demande"] ==
             GTFSTransport.find_tags_from_metadata(%{"some_stops_need_phone_driver" => true})

    assert ["description des correspondances"] == GTFSTransport.find_tags_from_metadata(%{"has_pathways" => true})
    assert ["tracés de lignes"] == GTFSTransport.find_tags_from_metadata(%{"has_shapes" => true})

    assert ["couleurs des lignes"] ==
             GTFSTransport.find_tags_from_metadata(%{"lines_with_custom_color_count" => 4, "lines_count" => 5})

    assert GTFSTransport.find_tags_from_metadata(%{"lines_with_custom_color_count" => 0, "has_fares" => false}) == []

    # Can find multiple tags
    assert GTFSTransport.find_tags_from_metadata(%{"has_fares" => true, "has_pathways" => true}) == [
             "tarifs",
             "description des correspondances"
           ]

    assert GTFSTransport.find_tags_from_metadata(%{
             "some_stops_need_phone_driver" => true,
             "some_stops_need_phone_agency" => true
           }) == ["transport à la demande"]

    # Does not crash when map is empty or some keys are not recognised
    assert GTFSTransport.find_tags_from_metadata(%{}) == []
    assert GTFSTransport.find_tags_from_metadata(%{"foo" => "bar"}) == []
  end
end
