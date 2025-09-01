defmodule Transport.IRVE.RawStaticConsolidationTest do
  use ExUnit.Case, async: false
  import Mox
  import Transport.S3.AggregatesUploader, only: [with_tmp_file: 1]
  doctest Transport.IRVE.RawStaticConsolidation, import: true

  setup :verify_on_exit!

  describe "build_aggregate_and_report!/1" do
    @tag :focus
    test "successfully processes valid IRVE resources and generates files" do
      with_tmp_file(fn data_file ->
        with_tmp_file(fn report_file ->
          # Mock the data.gouv.fr API response
          mock_datagouv_resources()

          # Mock HTTP requests for resource content
          mock_resource_downloads()

          # Execute the function
          options = [
            data_file: data_file,
            report_file: report_file
          ]

          assert :ok = Transport.IRVE.RawStaticConsolidation.build_aggregate_and_report!(options)

          # Verify data file was created and contains expected content
          assert File.exists?(data_file)
          data_content = File.read!(data_file)
          assert String.contains?(data_content, "id_pdc_itinerance")
          assert String.contains?(data_content, "original_dataset_id")
          assert String.contains?(data_content, "Métropole de Nulle Part")
          # TODO: check it’s a csv, etc.

          # Verify report file was created and contains expected content
          assert File.exists?(report_file)
          report_content = File.read!(report_file)
          assert String.contains?(report_content, "dataset_id")
          assert String.contains?(report_content, "resource_id")
        end)
      end)
    end
  end

  # Helper functions for mocking

  defp mock_datagouv_resources do
    # TODO: Mock Transport.IRVE.Extractor.datagouv_resources/0
    # You might need to use a different approach since this calls an external module
    # Consider using Application.put_env or a test-specific configuration
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
    # Mock the HTTP requests for downloading resource content
    # TODO change this
    Transport.Req.Mock
    |> expect(:get!, fn _url, _options ->
      %Req.Response{
        status: 200,
        body: [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()
      }
    end)
  end
end
