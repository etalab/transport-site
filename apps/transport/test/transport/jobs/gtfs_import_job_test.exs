defmodule Transport.Test.Transport.Jobs.GTFSImportJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def data_import_count do
    DB.Repo.aggregate(DB.DataImport, :count, :id)
  end

  test "import stops" do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: "xxx", datagouv_title: "coucou"})
    %{id: resource_id} = insert(:resource, dataset_id: dataset_id)
    %{id: resource_history_id} = insert(:resource_history, %{
      resource_id: resource_id,
      payload: %{"filename" => "some-file.zip"}
    })

    # TODO: reuse common code from Transport.Unzip.S3
    Transport.Unzip.S3.Mock
    |> expect(:get_file_stream, fn(file_in_zip, zip_file, bucket) ->
      # from payload
      assert zip_file == "some-file.zip"
      # from config
      assert bucket == "transport-data-gouv-fr-resource-history-test"

      # stub with a local file
      path = Path.dirname(__ENV__.file) |> Path.join("../../fixture/files/gtfs_import.zip")
      zip_file = Unzip.LocalFile.open(path)
      {:ok, unzip} = Unzip.new(zip_file)
      Unzip.file_stream!(unzip, file_in_zip)
    end)

    assert data_import_count() == 0
    _data_import_id = Transport.Jobs.GtfsToDB.import_gtfs_from_resource_history(resource_history_id, :stops)
    assert data_import_count() == 1

    # TODO: add test to ensure only one data import is kept, and only for the latest resource history. Previous
    # ones should be deleted
  end
end
