defmodule Transport.Test.Transport.Jobs.GTFSImportJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Transport.Test.FileStreamUtils
  import Ecto.Query

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def import_some_data do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: Ecto.UUID.generate(), datagouv_title: "coucou"})

    %{id: resource_id} = insert(:resource, dataset_id: dataset_id, format: "GTFS")

    %{id: resource_history_id} =
      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{"filename" => "some-file.zip"}
      })

    {dataset_id, resource_id, resource_history_id}
  end

  test "import without error" do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: Ecto.UUID.generate(), datagouv_title: "coucou"})

    %{id: resource_id} = insert(:resource, dataset_id: dataset_id, format: "GTFS")

    %{id: resource_history_id} =
      insert(:resource_history, %{
        resource_id: resource_id,
        payload: %{"filename" => "some-file.zip"}
      })

    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")

    {:ok, result} = perform_job(Transport.Jobs.GTFSImportStopsJob, %{})

    %{
      data_import_batch_id: data_import_batch_id,
      result: [%{resource_history_id: ^resource_history_id}]
    } = result

    assert DB.Repo.get(DB.DataImportBatch, data_import_batch_id)
  end

  # NOTE: ultimately, a better approach would be to reimport stops & everything in temporary tables
  # then drop previous tables, instead of manually removing items, but for now that will do.
  test "import must remove data imports for removed resource" do
    {_dataset_id, resource_id, _resource_history_id} = import_some_data()
    # import another one to make sure we can still create the materialized views
    import_some_data()

    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")

    {:ok, _result} = perform_job(Transport.Jobs.GTFSImportStopsJob, %{})
    assert DB.Repo.aggregate(DB.DataImport, :count, :id) == 2
    assert DB.Repo.aggregate(DB.GTFS.Stops, :count, :id) == 4
    assert DB.Repo.aggregate(DB.GTFS.Agency, :count, :id) == 2

    # then delete one of the resource
    query = from(r in DB.Resource, where: r.id == ^resource_id)
    query |> DB.Repo.delete_all()

    # resource history & data imports must still be there at this point
    assert DB.Repo.aggregate(DB.ResourceHistory, :count, :id) == 2
    assert DB.Repo.aggregate(DB.DataImport, :count, :id) == 2
    assert DB.Repo.aggregate(DB.GTFS.Stops, :count, :id) == 4
    assert DB.Repo.aggregate(DB.GTFS.Agency, :count, :id) == 2

    # deleting the resource and re-importing must result into data import removal
    {:ok, _result} = perform_job(Transport.Jobs.GTFSImportStopsJob, %{})
    assert DB.Repo.aggregate(DB.DataImport, :count, :id) == 1
    assert DB.Repo.aggregate(DB.GTFS.Stops, :count, :id) == 2
    assert DB.Repo.aggregate(DB.GTFS.Agency, :count, :id) == 1
  end

  test "import must remove data imports for inactive datasets" do
    {dataset_id, _resource_id, _resource_history_id} = import_some_data()
    # import another one to make sure we can still create the materialized views
    import_some_data()

    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")
    setup_get_file_stream_mox("some-file.zip")

    {:ok, _result} = perform_job(Transport.Jobs.GTFSImportStopsJob, %{})
    assert DB.Repo.aggregate(DB.DataImport, :count, :id) == 2
    assert DB.Repo.aggregate(DB.GTFS.Stops, :count, :id) == 2 * 2
    assert DB.Repo.aggregate(DB.GTFS.Agency, :count, :id) == 2

    # make one dataset inactive
    DB.Dataset
    |> DB.Repo.get_by(id: dataset_id)
    |> Ecto.Changeset.change(%{is_active: false})
    |> DB.Repo.update!()

    # data import must be removed
    {:ok, _result} = perform_job(Transport.Jobs.GTFSImportStopsJob, %{})
    assert DB.Repo.aggregate(DB.DataImport, :count, :id) == 1
    assert DB.Repo.aggregate(DB.GTFS.Stops, :count, :id) == 2
    assert DB.Repo.aggregate(DB.GTFS.Agency, :count, :id) == 1
  end
end
