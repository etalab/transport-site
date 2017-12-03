defmodule Transport.DataImprovement.DatasetRepositoryTest do
  use ExUnit.Case, async: true
  use ExVCR.Mock, adapter: ExVCR.Adapter.Hackney
  use TransportWeb.ConnCase # smell
  import Plug.Test # smell
  alias Transport.DataImprovement.{Dataset, DatasetRepository}
  alias Transport.Datagouvfr.Authentication # smell

  doctest DatasetRepository

  test "upload a dataset file", %{conn: conn} do
    file = %Plug.Upload{
      path: "test/fixture/files/gtfs.zip",
      filename: "gtfs.zip"
    }

    conn =
      init_test_session(
      conn,
      current_user: %{},
      client: Authentication.client("secret")
    )

    dataset = %Dataset{
      dataset_uuid: "5a0b1b240b5b39318769c3b1",
      file: file
    }

    use_cassette "dataset/upload-dataset-file-0" do
      assert {:ok, _} = DatasetRepository.update_file(dataset, conn)
    end
  end
end
