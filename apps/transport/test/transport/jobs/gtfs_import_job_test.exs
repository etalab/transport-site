defmodule Transport.Test.Transport.Jobs.GTFSImportJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Ecto.Query

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def data_import_count do
    DB.Repo.aggregate(DB.DataImport, :count, :id)
  end

  def data_import_ids do
    DB.Repo.all(from di in DB.DataImport, select: di.id, order_by: [asc: di.id])
  end

  defmodule ImportStops do
    @moduledoc """
    A module to import stops in a single `DB.DataImport` for a given resource, based on `resource_history_id`.
    """

    import Ecto.Query

    @doc """
    For the given `resource_history_id`, imports stops in a new `DB.DataImport`, then delete all related
    pre-existing `DB.DataImport` (either with the same `resource_history_id`, or for the same resource).
    """
    def import_stops(resource_history_id) do
      {:ok, data_import_id} = DB.Repo.transaction fn ->
        data_import_id = Transport.Jobs.GtfsToDB.import_gtfs_from_resource_history(resource_history_id, :stops)

        resource_id = DB.Repo.get_by(DB.ResourceHistory, id: resource_history_id).resource_id

        resource_history_ids = (from r in DB.Resource,
          join: rh in assoc(r, :resource_history),
          where: r.id == ^resource_id and rh.id != ^resource_history_id,
          select: rh.id)
        |> DB.Repo.all

        DB.DataImport
        # delete all previous data imports for the same resource history id
        |> where([di], di.resource_history_id == ^resource_history_id and di.id != ^data_import_id)
        # delete all previous data imports for the same resource but different resource history ids
        |> or_where([di], di.resource_history_id in ^resource_history_ids)
        |> DB.Repo.delete_all()

        data_import_id
      end

      data_import_id
    end
  end

  def setup_mox(zip_filename) do
    # TODO: reuse common code from Transport.Unzip.S3
    Transport.Unzip.S3.Mock
    |> expect(:get_file_stream, fn(file_in_zip, zip_file, bucket) ->
      # from payload
      assert zip_file == zip_filename
      # from config
      assert bucket == "transport-data-gouv-fr-resource-history-test"

      # stub with a local file
      path = Path.dirname(__ENV__.file) |> Path.join("../../fixture/files/gtfs_import.zip")
      zip_file = Unzip.LocalFile.open(path)
      {:ok, unzip} = Unzip.new(zip_file)
      Unzip.file_stream!(unzip, file_in_zip)
    end)
  end

  test "import stops" do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: "xxx", datagouv_title: "coucou"})
    %{id: resource_id} = insert(:resource, dataset_id: dataset_id)
    %{id: resource_history_id} = insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-file.zip"}})

    setup_mox("some-file.zip")
    assert data_import_count() == 0
    first_data_import_id = ImportStops.import_stops(resource_history_id)
    assert data_import_ids() == [first_data_import_id]

    # subsequent import must remove the previous import for same resource_history_id
    setup_mox("some-file.zip")
    second_data_import_id = ImportStops.import_stops(resource_history_id)
    assert data_import_ids() == [second_data_import_id]

    # subsequent import for a new resource_history_id on same resource should also remove previous imports
    %{id: new_resource_history_id} = insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-new-file.zip"}})
    setup_mox("some-new-file.zip")
    third_data_import_id = ImportStops.import_stops(new_resource_history_id)
    # TODO: based on one resource, grab back all the resource_history_id, then all the data_import, and delete all in batch except
    # the most recent one
    assert data_import_ids() == [third_data_import_id]
  end
end
