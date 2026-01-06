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

      # Check the content on S3
      bucket_name = "transport-data-gouv-fr-aggregates-test"
      date = Calendar.strftime(Date.utc_today(), "%Y%m%d")

      report_content =
        [
          %{
            "dataset_id" => "another-dataset-id",
            "dataset_title" => "another-dataset-title",
            "error_message" =>
              ~s|could not find column name "nom_station". The available columns are: ["accessibilite_pmr", "telephone_operateur", "coordonneesXY", "observations", "date_maj", "paiement_acte", "num_pdl", "code_insee_commune", "nom_enseigne", "puissance_nominale", "reservation", "adresse_station", "id_station_itinerance", "siren_amenageur", "paiement_cb", "prise_type_combo_ccs", "contact_operateur", "prise_type_ef", "implantation_station", "date_mise_en_service", "station_deux_roues", "cable_t2_attache", "horaires", "id_pdc_itinerance", "nbre_pdc", "raccordement", "id_station_local", "prise_type_autre", "nom_amenageur", "restriction_gabarit", "nom_operateur", "contact_amenageur", "id_pdc_local", "prise_type_2", "paiement_autre", "tarification", "prise_type_chademo", "gratuit", "condition_acces", "check_column_nom_amenageur_valid", "check_column_siren_amenageur_valid", "check_column_contact_amenageur_valid", "check_column_nom_operateur_valid", "check_column_contact_operateur_valid", "check_column_telephone_operateur_valid", "check_column_nom_enseigne_valid", "check_column_id_station_itinerance_valid", "check_column_id_station_local_valid"].\nIf you are attempting to interpolate a value, use ^nom_station.|,
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
        ]
        |> CSV.encode(headers: true)
        |> Enum.to_list()
        |> to_string()
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
        file_content: "be09aa4a95907235c9e3a984c79a41fd943a0465a1b5d69025d1994ed1c99a16"
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
      :ok = Transport.IRVE.SimpleConsolidation.process()

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

      # Start from factory payload but ensure all datasets have an organization
      payload =
        DB.Factory.IRVE.build_datagouv_page_payload()
        |> update_in(["data", Access.all(), "organization"], fn
          nil -> %{"id" => "fallback-org-id", "name" => "fallback-org", "page" => "http://fallback-org"}
          org -> org
        end)

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
