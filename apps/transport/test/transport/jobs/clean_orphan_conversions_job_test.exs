defmodule Transport.Test.Transport.Jobs.CleanOrphanConversionsJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias DB.Repo
  alias Transport.Jobs.CleanOrphanConversionsJob
  alias Transport.Test.S3TestUtils

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "CleanOrphanConversionsJob" do
    test "it deletes orphan rows" do
      uuid = Ecto.UUID.generate()
      filename = "folder/file.zip"

      data_conversion =
        insert(:data_conversion,
          resource_history_uuid: uuid,
          payload: %{"filename" => filename},
          convert_from: "GTFS",
          convert_to: "NeTEx"
        )

      S3TestUtils.s3_mocks_delete_object(Transport.S3.bucket_name(:history), filename)

      assert :ok == perform_job(CleanOrphanConversionsJob, %{})

      assert is_nil(Repo.reload(data_conversion))
    end

    test "it ignores rows with a matching ResourceHistory" do
      uuid = Ecto.UUID.generate()

      insert(:resource_history, payload: %{"uuid" => uuid})

      data_conversion =
        insert(:data_conversion,
          resource_history_uuid: uuid,
          payload: %{},
          convert_from: "GTFS",
          convert_to: "NeTEx"
        )

      assert :ok == perform_job(CleanOrphanConversionsJob, %{})

      refute is_nil(Repo.reload(data_conversion))
    end
  end
end
