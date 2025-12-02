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

      report = %{"summary" => %{"validatorVersion" => version}, "notices" => notices}
      {:successful, report}
    end)

    expect(Transport.Validators.MobilityDataGTFSValidatorClient.Mock, :report_html_url, fn ^job_id ->
      report_html_url
    end)

    assert :ok == MobilityDataGTFSValidator.validate_and_save(rh)

    assert [
             %DB.MultiValidation{
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
                 "max_severity" => %{"max_level" => "WARNING", "worst_occurrences" => 1},
                 "stats" => %{"WARNING" => 1},
                 "summary" => [%{"code" => "unusable_trip", "severity" => "WARNING", "totalNotices" => 2}]
               },
               max_error: "WARNING"
             }
           ] = DB.MultiValidation.with_result() |> DB.Repo.all()
  end
end
