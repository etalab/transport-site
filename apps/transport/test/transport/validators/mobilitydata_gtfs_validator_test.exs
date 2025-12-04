defmodule Transport.Validators.MobilityDataGTFSValidatorTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  alias Transport.Validators.MobilityDataGTFSValidator

  doctest Transport.Validators.MobilityDataGTFSValidator, import: true

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "validate_and_save for ResourceHistory" do
    gtfs_url = "https://example.com/gtfs"
    job_id = Ecto.UUID.generate()
    report_html_url = "https://example.com/#{job_id}/report.html"
    version = "4.2.0"
    %{id: rh_id} = rh = insert(:resource_history, payload: %{"permanent_url" => gtfs_url})

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :create_a_validation, fn ^gtfs_url ->
      job_id
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :get_a_validation, fn ^job_id ->
      notices = [
        %{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2, "sampleNotices" => ["foo", "bar"]}
      ]

      report = %{
        "summary" => %{
          "validatorVersion" => version,
          "counts" => %{"Stops" => 1337},
          "agencies" => [%{"url" => "https://example.com/agency", "name" => "Agency"}],
          "feedInfo" => %{"feedServiceWindowStart" => "2025-01-01", "feedServiceWindowEnd" => "2025-02-01"},
          "gtfsFeatures" => ["Continuous Stops", "Bike Allowed"]
        },
        "notices" => notices
      }

      {:successful, report}
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :report_html_url, fn ^job_id ->
      report_html_url
    end)

    assert :ok == MobilityDataGTFSValidator.validate_and_save(rh)

    assert [
             %DB.MultiValidation{
               id: mv_id,
               resource_history_id: ^rh_id,
               validator: "MobilityData GTFS Validator",
               validator_version: ^version,
               command: ^report_html_url,
               result: %{
                 "notices" => [
                   %{
                     "code" => "unusable_trip",
                     "sampleNotices" => ["foo", "bar"],
                     "severity" => "WARNING",
                     "totalNotices" => 2
                   }
                 ],
                 "summary" => %{"validatorVersion" => "4.2.0"}
               },
               digest: %{
                 "max_severity" => %{"max_level" => "WARNING", "worst_occurrences" => 2},
                 "stats" => %{"WARNING" => 2},
                 "summary" => [%{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2}]
               },
               max_error: "WARNING"
             }
           ] = DB.MultiValidation.with_result() |> DB.Repo.all()

    assert [
             %DB.ResourceMetadata{
               resource_id: nil,
               resource_history_id: ^rh_id,
               multi_validation_id: ^mv_id,
               metadata: %{
                 "agencies" => [%{"name" => "Agency", "url" => "https://example.com/agency"}],
                 "counts" => %{"Stops" => 1337},
                 "feedInfo" => %{"feedServiceWindowEnd" => "2025-02-01", "feedServiceWindowStart" => "2025-01-01"},
                 "start_date" => "2025-01-01",
                 "end_date" => "2025-02-01"
               },
               modes: [],
               features: ["Continuous Stops", "Bike Allowed"]
             }
           ] =
             DB.ResourceMetadata |> DB.Repo.all()
  end

  test "uses the GitHub validator version if the version is missing from the summary" do
    gtfs_url = "https://example.com/gtfs"
    job_id = Ecto.UUID.generate()
    report_html_url = "https://example.com/#{job_id}/report.html"
    version = "4.2.0"
    %{id: rh_id} = rh = insert(:resource_history, payload: %{"permanent_url" => gtfs_url})

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :create_a_validation, fn ^gtfs_url ->
      job_id
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :get_a_validation, fn ^job_id ->
      notices = [
        %{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2, "sampleNotices" => ["foo", "bar"]}
      ]

      {:successful, %{"summary" => %{}, "notices" => notices}}
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :report_html_url, fn ^job_id ->
      report_html_url
    end)

    # Call to GitHub to get the version
    expect(Transport.HTTPoison.Mock, :get!, fn url ->
      assert url == "https://api.github.com/repos/MobilityData/gtfs-validator/releases/latest"
      %HTTPoison.Response{status_code: 200, body: %{tag_name: "v" <> version} |> Jason.encode!()}
    end)

    assert :ok == MobilityDataGTFSValidator.validate_and_save(rh)

    assert [
             %DB.MultiValidation{
               resource_history_id: ^rh_id,
               validator: "MobilityData GTFS Validator",
               validator_version: ^version,
               command: ^report_html_url
             }
           ] = DB.MultiValidation.with_result() |> DB.Repo.all()
  end

  test "validate_and_save when error" do
    gtfs_url = "https://example.com/gtfs"
    job_id = Ecto.UUID.generate()
    %{id: rh_id} = rh = insert(:resource_history, payload: %{"permanent_url" => gtfs_url})

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :create_a_validation, fn ^gtfs_url ->
      job_id
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :get_a_validation, fn ^job_id ->
      {:error, %{"reason" => "nope"}}
    end)

    expect(Transport.HTTPoison.Mock, :get!, fn url ->
      assert url == "https://api.github.com/repos/MobilityData/gtfs-validator/releases/latest"
      %HTTPoison.Response{status_code: 200, body: %{tag_name: "4.2.0"} |> Jason.encode!()}
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :report_html_url, fn ^job_id ->
      "https://example.com/report"
    end)

    assert :ok == MobilityDataGTFSValidator.validate_and_save(rh)

    assert [
             mv = %DB.MultiValidation{
               resource_history_id: ^rh_id,
               validator: "MobilityData GTFS Validator",
               result: %{"reason" => "nope", "validation_performed" => false}
             }
           ] = DB.MultiValidation.with_result() |> DB.Repo.all()

    refute TransportWeb.DatasetView.multi_validation_performed?(mv)
  end

  test "validate_and_save when unexpected_validation_status" do
    gtfs_url = "https://example.com/gtfs"
    job_id = Ecto.UUID.generate()
    %{id: rh_id} = rh = insert(:resource_history, payload: %{"permanent_url" => gtfs_url})

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :create_a_validation, fn ^gtfs_url ->
      job_id
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :get_a_validation, fn ^job_id ->
      :unexpected_validation_status
    end)

    expect(Transport.HTTPoison.Mock, :get!, fn url ->
      assert url == "https://api.github.com/repos/MobilityData/gtfs-validator/releases/latest"
      %HTTPoison.Response{status_code: 200, body: %{tag_name: "4.2.0"} |> Jason.encode!()}
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :report_html_url, fn ^job_id ->
      "https://example.com/report"
    end)

    assert :ok == MobilityDataGTFSValidator.validate_and_save(rh)

    assert [
             mv = %DB.MultiValidation{
               resource_history_id: ^rh_id,
               validator: "MobilityData GTFS Validator",
               result: %{"reason" => "unexpected_validation_status", "validation_performed" => false}
             }
           ] = DB.MultiValidation.with_result() |> DB.Repo.all()

    refute TransportWeb.DatasetView.multi_validation_performed?(mv)
  end
end
