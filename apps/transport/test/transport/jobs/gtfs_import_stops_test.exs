defmodule Transport.Test.Transport.Jobs.GTFSImportStopsTest do
  # due to materialized views creations, we cannot go async
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Ecto.Query
  import Transport.Test.FileStreamUtils
  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def data_import_ids do
    DB.Repo.all(from(di in DB.DataImport, select: di.id, order_by: [asc: di.id]))
  end

  test "import stops" do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: "xxx", datagouv_title: "coucou"})
    %{id: resource_id} = insert(:resource, dataset_id: dataset_id)

    %{id: resource_history_id} =
      insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-file.zip"}})

    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")
    assert data_import_ids() == []
    first_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(resource_history_id)
    assert data_import_ids() == [first_data_import_id]

    # subsequent import must remove the previous import for same resource_history_id
    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")
    second_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(resource_history_id)
    assert data_import_ids() == [second_data_import_id]

    # subsequent import for a new resource_history_id on same resource should also remove previous imports
    %{id: new_resource_history_id} =
      insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-new-file.zip"}})

    setup_get_file_stream_mox("some-new-file.zip")
    setup_get_file_stream_mox("some-new-file.zip")
    third_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(new_resource_history_id)
    assert data_import_ids() == [third_data_import_id]

    # other resources should not be impacted by import
    setup_get_file_stream_mox("some-other-file.zip")
    setup_get_file_stream_mox("some-other-file.zip")
    %{id: other_dataset_id} = insert(:dataset, %{datagouv_id: "yyy"})
    %{id: other_resource_id} = insert(:resource, dataset_id: other_dataset_id)

    %{id: other_resource_history_id} =
      insert(:resource_history, %{resource_id: other_resource_id, payload: %{"filename" => "some-other-file.zip"}})

    other_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(other_resource_history_id)

    assert data_import_ids() == [third_data_import_id, other_data_import_id]

    %{id: new_resource_history_id} =
      insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-new-file.zip"}})

    setup_get_file_stream_mox("some-new-file.zip")
    setup_get_file_stream_mox("some-new-file.zip")
    fourth_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(new_resource_history_id)
    assert data_import_ids() == [other_data_import_id, fourth_data_import_id]
  end
end
