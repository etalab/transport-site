defmodule Transport.IRVE.SimpleConsolidationTest do
  use ExUnit.Case, async: true
  import Mox
  import Ecto.Query

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    :verify_on_exit!
    :ok
  end

  describe "process/0" do
    # grouping successful & error test for now, will be improved
    test "writes pdcs for valid file, and not for invalid file" do
      # Mock the data.gouv.fr API response
      mock_datagouv_resources()

      # Mock HTTP requests for resource content, one is valid, the other is not
      mock_resource_downloads()

      assert DB.Repo.aggregate(DB.IRVEValidFile, :count, :id) == 0
      assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 0

      # Run the consolidation process
      :ok = Transport.IRVE.SimpleConsolidation.process(destination: :local_disk)

      # Check that we have imported a file and its unique PDC in the DB
      [first_import_file] =
        DB.IRVEValidFile
        |> order_by([f], asc: f.dataset_datagouv_id)
        |> DB.Repo.all()

      assert first_import_file.dataset_datagouv_id == "the-dataset-id"
      assert first_import_file.resource_datagouv_id == "the-resource-id"

      assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 1

      # There should be no leftover temporary files
      refute File.exists?(System.tmp_dir!() |> Path.join("irve-resource-the-resource-id.dat"))
      refute File.exists?(System.tmp_dir!() |> Path.join("irve-resource-another-resource-id.dat"))

      file_name = "irve_static_consolidation_v2_report.csv"

      # Check the generated report, here it’s stored on local disk (not default S3)
      assert File.exists?(file_name)
      report_content = file_name |> File.stream!() |> CSV.decode!(headers: true) |> Enum.to_list()

      [
        %{
          "dataset_id" => "another-dataset-id",
          "dataset_title" => "another-dataset-title",
          "error_message" => error_message,
          "error_type" => "ArgumentError",
          "resource_id" => "another-resource-id",
          "status" => "error_occurred",
          "url" => "https://static.data.gouv.fr/resources/another-irve-url-2024/data.csv"
        },
        %{
          "dataset_id" => "the-dataset-id",
          "dataset_title" => "the-dataset-title",
          "error_message" => "",
          "error_type" => "",
          "resource_id" => "the-resource-id",
          "status" => "import_successful",
          "url" => "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv"
        }
      ] = report_content

      assert error_message =~ "could not find column name \"nom_station\"."
      File.rm!(file_name)
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
    Transport.Req.Mock
    # We need to have a single call with single expect to work properly
    # because Mox matches in order of definition
    #  and task process order is not deterministic
    |> expect(:get!, 2, fn _url, options ->
      # We deal with different cases with a pattern match inside the function
      resource_mock(options)
    end)
  end

  # A correct resource!
  def resource_mock(
        into: into,
        decode_body: false,
        compressed: false,
        url: "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv"
      ) do
    path = into.path
    body = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()
    File.write!(path, body)

    %Req.Response{
      status: 200,
      body: File.stream!(path)
    }
  end

  # This one won’t be valid, we remove a required column
  def resource_mock(
        into: into,
        decode_body: false,
        compressed: false,
        url: "https://static.data.gouv.fr/resources/another-irve-url-2024/data.csv"
      ) do
    path = into.path
    body = [DB.Factory.IRVE.generate_row() |> Map.pop!("nom_station") |> elem(1)] |> DB.Factory.IRVE.to_csv_body()
    File.write!(path, body)

    %Req.Response{
      status: 200,
      body: File.stream!(path)
    }
  end
end
