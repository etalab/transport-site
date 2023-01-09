defmodule Transport.Test.Transport.Jobs.GTFSImportJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Transport.Test.FileStreamUtils

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "import without error" do
    %{id: dataset_id} = insert(:dataset, %{datagouv_id: "xxx", datagouv_title: "coucou"})
    %{id: resource_id} = insert(:resource, dataset_id: dataset_id, format: "GTFS")

    %{id: resource_history_id} =
      insert(:resource_history, %{resource_id: resource_id, payload: %{"filename" => "some-file.zip"}})

    setup_get_file_stream_mox("some-file.zip")

    {:ok, result} = perform_job(Transport.Jobs.GTFSImportStopsJob, %{})

    [{:ok, %{resource_history_id: ^resource_history_id}}] = result
  end
end
