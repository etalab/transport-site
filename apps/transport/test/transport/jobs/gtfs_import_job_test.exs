defmodule Transport.Test.Transport.Jobs.GTFSImportJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "stops import" do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: "xxx", datagouv_title: "coucou"})
    %{id: resource_id} = insert(:resource, dataset_id: dataset_id)
    %{id: resource_history_id} = insert(:resource_history, %{
      resource_id: resource_id,
      payload: %{"filename" => "some-file.zip"}
    })

    data_import_id = Transport.Jobs.GtfsToDB.import_gtfs_from_resource_history(resource_history_id, :stops)
  end
end
