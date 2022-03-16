defmodule Transport.Jobs.Backfill.ResourceHistoryFileSizeTest do
  use ExUnit.Case
  import Transport.Jobs.Backfill.ResourceHistoryFileSize
  import DB.Factory
  import Mox

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "update a zip resource history" do
    %{id: id} =
      insert(:resource_history, %{
        datagouv_id: datagouv_id = "datagouv_id",
        payload: %{"total_compressed_size" => size = "10", "other_field" => "other_value"}
      })

    update_resource_filesize(id)

    res = DB.ResourceHistory |> DB.Repo.get!(id)

    assert res.datagouv_id == datagouv_id
    assert res.payload == %{"total_compressed_size" => size, "filesize" => size, "other_field" => "other_value"}
  end

  test "update an other resource history" do
    %{id: id} =
      insert(:resource_history, %{
        datagouv_id: datagouv_id = "datagouv_id",
        payload: %{"permanent_url" => url = "https//example.com", "other_field" => "other_value"}
      })

    size = 1000

    Transport.HTTPoison.Mock
    |> expect(:head, 1, fn ^url ->
      {:ok, %{headers: [{"coucou", "toi"}, {"content-length", size}]}}
    end)

    update_resource_filesize(id)

    res = DB.ResourceHistory |> DB.Repo.get!(id)

    assert res.datagouv_id == datagouv_id
    assert res.payload == %{"permanent_url" => url, "filesize" => size, "other_field" => "other_value"}
  end
end
