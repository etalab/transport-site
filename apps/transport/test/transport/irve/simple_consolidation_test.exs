defmodule Transport.IRVE.SimpleConsolidationTest do
  use ExUnit.Case, async: false
  import Mox
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    :verify_on_exit!
    :ok
  end

  describe "process/0" do
    test "writes pdcs for valid files" do
      # Mock the data.gouv.fr API response
      mock_datagouv_resources()

      # Mock HTTP requests for resource content

      [resource_file_path_1, resource_file_path_2] = mock_resource_downloads()

      assert DB.Repo.aggregate(DB.IRVEValidFile, :count, :id) == 0
      assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 0

      result = Transport.IRVE.SimpleConsolidation.process()

      assert result == [{:ok, true}, {:ok, true}]

      # Verify data file was created and contains expected content

      [first_import_file, _second_import_file] =
        DB.IRVEValidFile
        |> order_by([f], asc: f.dataset_datagouv_id)
        |> DB.Repo.all()

      assert first_import_file.dataset_datagouv_id == "another-dataset-id"
      assert first_import_file.resource_datagouv_id == "another-resource-id"

      assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 2

      refute File.exists?(resource_file_path_1)
      refute File.exists?(resource_file_path_2)
    end
  end

  defp mock_datagouv_resources do
    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] ==
               "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique&page_size=100"

      %Req.Response{status: 200, body: DB.Factory.IRVE.build_datagouv_initial_pagination_payload(page_size: 100)}
    end)

    # next requests are same queries but paginated and helping
    Transport.Req.Mock
    |> expect(:get!, fn _request, options ->
      assert options[:url] ==
               "https://www.data.gouv.fr/api/1/datasets/?schema=etalab/schema-irve-statique&page=1&page_size=100"

      %Req.Response{
        status: 200,
        body: DB.Factory.IRVE.build_datagouv_page_payload()
      }
    end)
  end

  defp mock_resource_downloads do
    resource_file_path_1 = System.tmp_dir!() |> Path.join("irve-resource-the-resource-id.dat")
    resource_file_path_2 = System.tmp_dir!() |> Path.join("irve-resource-another-resource-id.dat")

    body = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()
    File.write!(resource_file_path_1, body)
    File.write!(resource_file_path_2, body)

    Transport.Req.Mock
    |> expect(:get!, 2, fn _url, _options ->
      %Req.Response{
        status: 200,
        body: File.stream!(resource_file_path_1)
      }
    end)

    [resource_file_path_1, resource_file_path_2]
  end
end
