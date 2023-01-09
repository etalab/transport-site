defmodule Transport.Test.Transport.Jobs.GTFSImportStopsTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Ecto.Query

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def data_import_ids do
    DB.Repo.all(from(di in DB.DataImport, select: di.id, order_by: [asc: di.id]))
  end

  def setup_mox(zip_filename) do
    # NOTE: it will be possible to reuse common code from Transport.Unzip.S3 in there
    Transport.Unzip.S3.Mock
    |> expect(:get_file_stream, fn file_in_zip, zip_file, bucket ->
      # from payload
      assert zip_file == zip_filename
      # from config
      assert bucket == "transport-data-gouv-fr-resource-history-test"

      # stub with a local file
      path = "#{__DIR__}/../../fixture/files/gtfs_import.zip"
      zip_file = Unzip.LocalFile.open(path)
      {:ok, unzip} = Unzip.new(zip_file)
      Unzip.file_stream!(unzip, file_in_zip)
    end)
  end

  test "import stops" do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: "xxx", datagouv_title: "coucou"})
    %{id: resource_id} = insert(:resource, dataset_id: dataset_id)

    %{id: resource_history_id} =
      insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-file.zip"}})

    setup_mox("some-file.zip")
    assert data_import_ids() == []
    first_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(resource_history_id)
    assert data_import_ids() == [first_data_import_id]

    # subsequent import must remove the previous import for same resource_history_id
    setup_mox("some-file.zip")
    second_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(resource_history_id)
    assert data_import_ids() == [second_data_import_id]

    # subsequent import for a new resource_history_id on same resource should also remove previous imports
    %{id: new_resource_history_id} =
      insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-new-file.zip"}})

    setup_mox("some-new-file.zip")
    third_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(new_resource_history_id)
    assert data_import_ids() == [third_data_import_id]

    # other resources should not be impacted by import
    setup_mox("some-other-file.zip")
    %{id: other_dataset_id} = insert(:dataset, %{datagouv_id: "xxx"})
    %{id: other_resource_id} = insert(:resource, dataset_id: other_dataset_id)

    %{id: other_resource_history_id} =
      insert(:resource_history, %{resource_id: other_resource_id, payload: %{"filename" => "some-other-file.zip"}})

    other_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(other_resource_history_id)

    assert data_import_ids() == [third_data_import_id, other_data_import_id]

    %{id: new_resource_history_id} =
      insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-new-file.zip"}})

    setup_mox("some-new-file.zip")
    fourth_data_import_id = Transport.GTFSImportStops.import_stops_and_remove_previous(new_resource_history_id)
    assert data_import_ids() == [other_data_import_id, fourth_data_import_id]
  end
end
