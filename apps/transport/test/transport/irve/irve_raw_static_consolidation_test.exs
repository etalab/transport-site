defmodule Transport.IRVE.RawStaticConsolidationTest do
  use ExUnit.Case, async: false
  import Mox
  import Transport.S3.AggregatesUploader, only: [with_tmp_file: 1]
  doctest Transport.IRVE.RawStaticConsolidation, import: true

  setup :verify_on_exit!

  describe "build_aggregate_and_report!/1" do
    test "successfully processes valid IRVE resources and generates files" do
      with_tmp_file(fn data_file ->
        with_tmp_file(fn report_file ->
          # Mock the data.gouv.fr API response
          mock_datagouv_resources()

          # Mock HTTP requests for resource content
          resource_file_path = mock_resource_downloads()

          # Execute the function
          options = [
            data_file: data_file,
            report_file: report_file
          ]

          assert [
                   %Transport.IRVE.ReportItem{resource_id: "another-resource-id"},
                   %Transport.IRVE.ReportItem{resource_id: "the-resource-id"}
                 ] = Transport.IRVE.RawStaticConsolidation.build_aggregate_and_report!(options)

          # Verify data file was created and contains expected content
          assert File.exists?(data_file)
          # Only one PDC line expected, even if two resources were given (the other had no organization)
          [headers, pdc_line] = data_file |> File.stream!() |> CSV.decode!() |> Enum.into([])

          assert headers ==
                   (Transport.IRVE.StaticIRVESchema.field_names_list() -- ["coordonneesXY", "cable_t2_attache"]) ++
                     ["longitude", "latitude", "original_dataset_id", "original_resource_id"]

          assert pdc_line == [
                   "Métropole de Nulle Part",
                   "123456782",
                   "amenageur@example.com",
                   "Opérateur de Charge",
                   "operateur@example.com",
                   "0199456782",
                   "Réseau de recharge",
                   "FRPAN99P12345678",
                   "station_001",
                   "Ma Station",
                   "Voirie",
                   "26 rue des écluses, 17430 Champdolent",
                   "17085",
                   "1",
                   "FRPAN99E12345678",
                   "pdc_001",
                   "22.0",
                   "false",
                   "true",
                   "false",
                   "false",
                   "false",
                   "false",
                   "true",
                   "true",
                   "true",
                   "2,50€ / 30min puis 0,025€ / minute",
                   "Accès libre",
                   "false",
                   "24/7",
                   "Accessible mais non réservé PMR",
                   "Hauteur maximale 2.30m",
                   "false",
                   "Direct",
                   "12345678912345",
                   "2024-10-02",
                   "Station située au niveau -1 du parking",
                   "2024-10-17",
                   "-0.799141",
                   "45.91914",
                   "the-dataset-id",
                   "the-resource-id"
                 ]

          # Verify report file was created and contains expected content
          assert File.exists?(report_file)
          report_content = File.read!(report_file)
          assert String.contains?(report_content, "dataset_id")
          assert String.contains?(report_content, "resource_id")
          assert String.contains?(report_content, "%RuntimeError{message: \"\"producer is not an organization\"\"}")

          # The file created on the disk (mocking Req behavior) should be removed.
          # The consolidation job takes care of cleaning up those files, but here we’re testing the module, not the job.
          # (And it’s expected that the module keeps these files on the disk).
          File.rm!(resource_file_path)
        end)
      end)
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
    resource_file_path = System.tmp_dir!() |> Path.join("irve_raw_#{Ecto.UUID.generate()}")

    body = [DB.Factory.IRVE.generate_row()] |> DB.Factory.IRVE.to_csv_body()
    File.write!(resource_file_path, body)

    Transport.Req.Mock
    |> expect(:get!, 2, fn _url, _options ->
      %Req.Response{
        status: 200,
        body: File.stream!(resource_file_path)
      }
    end)

    resource_file_path
  end
end
