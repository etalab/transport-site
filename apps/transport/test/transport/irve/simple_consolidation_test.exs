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
      # Note: this consolidation only downloads resources published by orgs
      # So it’s 2 calls here (see the mock)
      mock_resource_downloads()

      assert DB.Repo.aggregate(DB.IRVEValidFile, :count, :id) == 0
      assert DB.Repo.aggregate(DB.IRVEValidPDC, :count, :id) == 0

      # Check the content on S3
      bucket_name = "transport-data-gouv-fr-aggregates-test"
      date = Calendar.strftime(Date.utc_today(), "%Y%m%d")

      # Create a DataFrame and select columns in the same order as the actual implementation
      report_content =
        [
          %{
            "dataset_id" => "another-dataset-id",
            "resource_id" => "another-resource-id",
            "status" => "error_occurred",
            "error_type" => "ArgumentError",
            "estimated_pdc_count" => "1",
            "url" => "https://static.data.gouv.fr/resources/another-irve-url-2024/data.csv",
            "dataset_title" => "another-dataset-title",
            # TODO rework to only compare the part of the message that matters
            "error_message" =>
              ~s|could not find column name "nom_station". The available columns are: ["accessibilite_pmr", "telephone_operateur", "coordonneesXY", "observations", "date_maj", "num_pdl", "code_insee_commune", "nom_enseigne", "puissance_nominale", "adresse_station", "id_station_itinerance", "siren_amenageur", "contact_operateur", "implantation_station", "date_mise_en_service", "horaires", "id_pdc_itinerance", "nbre_pdc", "raccordement", "id_station_local", "nom_amenageur", "restriction_gabarit", "nom_operateur", "contact_amenageur", "id_pdc_local", "tarification", "condition_acces", "prise_type_ef", "prise_type_2", "prise_type_combo_ccs", "prise_type_chademo", "prise_type_autre", "gratuit", "paiement_acte", "paiement_cb", "paiement_autre", "reservation", "station_deux_roues", "cable_t2_attache", "check_column_nom_amenageur_valid", "check_column_siren_amenageur_valid", "check_column_contact_amenageur_valid", "check_column_nom_operateur_valid", "check_column_contact_operateur_valid", "check_column_telephone_operateur_valid", "check_column_nom_enseigne_valid", "check_column_id_station_itinerance_valid", "check_column_id_station_local_valid"].\nIf you are attempting to interpolate a value, use ^nom_station.|
          },
          %{
            "dataset_id" => "individual-published-dataset-id",
            "resource_id" => "individual-published-resource-id",
            "status" => "error_occurred",
            "error_type" => "RuntimeError",
            "estimated_pdc_count" => "1",
            "url" => "https://static.data.gouv.fr/resources/individual-published-irve-url-2024/data.csv",
            "dataset_title" => "individual-published-dataset-title",
            "error_message" => "producer is not an organization"
          },
          %{
            "dataset_id" => "the-dataset-id",
            "resource_id" => "the-resource-id",
            "status" => "import_successful",
            "error_type" => nil,
            "estimated_pdc_count" => "1",
            "url" => "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv",
            "dataset_title" => "the-dataset-title",
            "error_message" => nil
          }
        ]
        |> Explorer.DataFrame.new()
        # Use the same column order as in the actual implementation
        |> Explorer.DataFrame.select([
          "dataset_id",
          "resource_id",
          "status",
          "error_type",
          "estimated_pdc_count",
          "url",
          "dataset_title",
          "error_message"
        ])
        |> Explorer.DataFrame.dump_csv!()
        |> String.replace("\r\n", "\n")

      Transport.Test.S3TestUtils.s3_mock_stream_file(
        start_path: "irve_static_consolidation_v2_report_#{date}",
        bucket: bucket_name,
        acl: :private,
        file_content: report_content
      )

      Transport.Test.S3TestUtils.s3_mock_stream_file(
        start_path: "irve_static_consolidation_v2_report_#{date}",
        bucket: bucket_name,
        acl: :private,
        file_content: "fec929446c9c5b606997527a789a416512ddf06ffd39fc627a422050f23fa9db"
      )

      Transport.Test.S3TestUtils.s3_mocks_remote_copy_file(
        bucket_name,
        "irve_static_consolidation_v2_report_#{date}",
        "irve_static_consolidation_v2_report.csv"
      )

      Transport.Test.S3TestUtils.s3_mocks_remote_copy_file(
        bucket_name,
        "irve_static_consolidation_v2_report_#{date}",
        "irve_static_consolidation_v2_report.csv.sha256sum"
      )

      # Run the consolidation process
      {:ok, %Explorer.DataFrame{} = report_df} = Transport.IRVE.SimpleConsolidation.process()

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

      payload =
        DB.Factory.IRVE.build_datagouv_page_payload()

      %Req.Response{
        status: 200,
        body: payload
      }
    end)
  end

  defp mock_resource_downloads do
    Transport.Req.Mock
    # We need to have a single call with single expect to work properly
    # because Mox matches in order of definition
    #  and task process order is not deterministic
    |> expect(:get!, 3, fn _url, options ->
      # We deal with different cases with a pattern match inside the function
      resource_mock(options)
    end)
  end

  @valid_url "https://static.data.gouv.fr/resources/some-irve-url-2024/data.csv"
  @individual_published_url "https://static.data.gouv.fr/resources/individual-published-irve-url-2024/data.csv"
  @invalid_url "https://static.data.gouv.fr/resources/another-irve-url-2024/data.csv"

  # A correct resource
  defp resource_mock(into: into, decode_body: false, compressed: false, url: @valid_url) do
    build_resource_response(into.path, [DB.Factory.IRVE.generate_row()])
  end

  # Invalid: missing required column nom_station
  defp resource_mock(into: into, decode_body: false, compressed: false, url: @invalid_url) do
    build_resource_response(into.path, [DB.Factory.IRVE.generate_row() |> Map.delete("nom_station")])
  end

  # Published by individual, valid but should be skipped. Downloaded for line count.
  defp resource_mock(into: into, decode_body: false, compressed: false, url: @individual_published_url) do
    build_resource_response(into.path, [DB.Factory.IRVE.generate_row()])
  end

  defp build_resource_response(path, rows) do
    body = DB.Factory.IRVE.to_csv_body(rows)
    File.write!(path, body)
    %Req.Response{status: 200, body: File.stream!(path)}
  end
end
