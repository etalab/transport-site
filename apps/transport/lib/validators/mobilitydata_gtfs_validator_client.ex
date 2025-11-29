defmodule Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper do
  @moduledoc """
  A client for the Canonical GTFS validator.
  https://gtfs-validator.mobilitydata.org
  """

  @callback create_a_validation(binary()) :: binary()
  @callback get_a_validation(binary()) ::
              :pending | {:successful, map()} | {:error, map()} | :unexpected_validation_status
  @callback report_html_url(binary()) :: binary()
  def impl, do: Application.get_env(:transport, :mobilitydata_gtfs_validator_client)
end

defmodule Transport.Validators.MobilityDataGTFSValidatorClient do
  @moduledoc """
  Implementation of the Canonical GTFS Validator client.
  """
  @jobs_base_url "https://gtfs-validator-web-mbzoxaljzq-ue.a.run.app"
  @results_base_url "https://gtfs-validator-results.mobilitydata.org"
  @behaviour Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper

  @impl Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper
  def create_a_validation(gtfs_url) do
    url = @jobs_base_url <> "/create-job"

    data =
      %{
        "countryCode" => "FR",
        "url" => gtfs_url
      }
      |> Jason.encode!()

    %HTTPoison.Response{status_code: 200, body: body} =
      http_client().post!(url, data, [{"content-type", "application/json"}])

    body |> Jason.decode!() |> Map.fetch!("jobId")
  end

  @impl Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper
  def get_a_validation(job_id) do
    %HTTPoison.Response{status_code: status, body: body} = http_client().get!(execution_result_url(job_id))

    cond do
      status == 404 ->
        :pending

      status == 200 ->
        json = body |> Jason.decode!()

        case Map.get(json, "status") do
          "success" ->
            %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(report_url(job_id))
            {:successful, body |> Jason.decode!()}

          "error" ->
            %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(report_url(job_id))
            report_json = body |> Jason.decode!()
            %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(system_errors_url(job_id))
            system_errors = body |> Jason.decode!()
            {:error, Map.put(report_json, "system_errors", system_errors)}

          _ ->
            :unexpected_validation_status
        end

      true ->
        :unexpected_validation_status
    end
  end

  @impl Transport.Validators.MobilityDataGTFSValidatorClient.Wrapper
  def report_html_url(job_id), do: @results_base_url <> "/#{job_id}/report.html"

  defp execution_result_url(job_id), do: @results_base_url <> "/#{job_id}/execution_result.json"
  defp report_url(job_id), do: @results_base_url <> "/#{job_id}/report.json"
  defp system_errors_url(job_id), do: @results_base_url <> "/#{job_id}/system_errors.json"

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
