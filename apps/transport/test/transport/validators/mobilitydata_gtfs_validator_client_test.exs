defmodule Transport.Validators.MobilityDataGTFSValidatorClientTest do
  use ExUnit.Case, async: true
  import Mox
  alias Transport.Validators.MobilityDataGTFSValidatorClient

  setup :verify_on_exit!

  test "create_a_validation" do
    job_id = Ecto.UUID.generate()
    gtfs_url = "https://example.com/#{Ecto.UUID.generate()}"

    Transport.HTTPoison.Mock
    |> expect(:post!, fn url, args, [{"content-type", "application/json"}] ->
      assert url == "https://gtfs-validator-web-mbzoxaljzq-ue.a.run.app/create-job"

      assert args ==
               %{
                 "countryCode" => "FR",
                 "url" => gtfs_url
               }
               |> Jason.encode!()

      body = %{jobId: job_id} |> Jason.encode!()
      %HTTPoison.Response{status_code: 200, body: body}
    end)

    assert job_id == MobilityDataGTFSValidatorClient.create_a_validation(gtfs_url)
  end

  describe "get_a_validation" do
    test "successful" do
      job_id = Ecto.UUID.generate()
      execution_result_url = "https://gtfs-validator-results.mobilitydata.org/#{job_id}/execution_result.json"
      report_url = "https://gtfs-validator-results.mobilitydata.org/#{job_id}/report.json"

      expect(Transport.HTTPoison.Mock, :get!, fn ^execution_result_url ->
        %HTTPoison.Response{status_code: 404}
      end)

      assert :pending == MobilityDataGTFSValidatorClient.get_a_validation(job_id)

      expect(Transport.HTTPoison.Mock, :get!, fn ^execution_result_url ->
        %HTTPoison.Response{status_code: 200, body: %{"status" => "success"} |> Jason.encode!()}
      end)

      expect(Transport.HTTPoison.Mock, :get!, fn ^report_url ->
        %HTTPoison.Response{status_code: 200, body: %{"data" => 42} |> Jason.encode!()}
      end)

      assert {:successful, %{"data" => 42}} == MobilityDataGTFSValidatorClient.get_a_validation(job_id)
    end

    test "error" do
      job_id = Ecto.UUID.generate()
      execution_result_url = "https://gtfs-validator-results.mobilitydata.org/#{job_id}/execution_result.json"
      report_url = "https://gtfs-validator-results.mobilitydata.org/#{job_id}/report.json"
      system_errors_url = "https://gtfs-validator-results.mobilitydata.org/#{job_id}/system_errors.json"

      expect(Transport.HTTPoison.Mock, :get!, fn ^execution_result_url ->
        %HTTPoison.Response{status_code: 200, body: %{"status" => "error"} |> Jason.encode!()}
      end)

      expect(Transport.HTTPoison.Mock, :get!, fn ^report_url ->
        %HTTPoison.Response{status_code: 200, body: %{"data" => 42} |> Jason.encode!()}
      end)

      expect(Transport.HTTPoison.Mock, :get!, fn ^system_errors_url ->
        %HTTPoison.Response{status_code: 200, body: %{"error_details" => 1337} |> Jason.encode!()}
      end)

      assert {:error, %{"data" => 42, "system_errors" => %{"error_details" => 1337}}} ==
               MobilityDataGTFSValidatorClient.get_a_validation(job_id)
    end

    test "unexpected_validation_status" do
      job_id = Ecto.UUID.generate()
      execution_result_url = "https://gtfs-validator-results.mobilitydata.org/#{job_id}/execution_result.json"

      expect(Transport.HTTPoison.Mock, :get!, fn ^execution_result_url ->
        %HTTPoison.Response{status_code: 500}
      end)

      assert :unexpected_validation_status == MobilityDataGTFSValidatorClient.get_a_validation(job_id)
    end
  end
end
