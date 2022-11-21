defmodule Transport.Validators.ValidataLot2 do
  @moduledoc """
  Validate JSON files with Validata JSON API
  https://git.opendatafrance.net/validata/validata-json
  """

  @behaviour Transport.Validators.Validator

  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{
        id: resource_history_id,
        payload:
          %{
            "permanent_url" => url,
            "schema_name" => schema_name,
            "schema_version" => schema_version
          } = payload
      })
      when is_binary(schema_name) do
    schema_version = schema_version || Map.get(payload, "latest_schema_version_to_date", "latest")
    {:ok, validation} = perform_validation(schema_name, schema_version, url)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      result: validation,
      resource_history_id: resource_history_id,
      validator_version: validator_version(),
      command: validation_url(schema_name, schema_version, url)
    }
    |> DB.Repo.insert!()

    :ok
  end

  def base_url, do: "https://json.validator.validata.fr"

  def validation_url(schema_name, schema_version, url) do
    schema_url = Transport.Shared.Schemas.schema_url(schema_name, schema_version)
    base_url() <> "/url_validation_job?data=#{url}&schema=#{schema_url}"
  end

  def perform_validation(schema_name, schema_version, url) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    validation_url = validation_url(schema_name, schema_version, url)

    case http_client.post(validation_url, "") do
      {:ok,
       %HTTPoison.Response{
         status_code: 201,
         body: job_id
       }} ->
        job_id |> String.replace("\"", "") |> get_api_result()

      _ ->
        {:error, "validation server error, job creation failed"}
    end
  end

  def get_api_result(job_id) do
    poll_url = "https://json.validator.validata.fr/job/#{job_id}"
    poll_api_result(poll_url, 0)
  end

  def poll_api_result(_url, nb_tries) when nb_tries > 30 do
    {:error, "validation timeout, too many polling attempts"}
  end

  def poll_api_result(url, nb_tries) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    case http_client.get(url) do
      {:ok,
       %HTTPoison.Response{
         status_code: 303
       }} ->
        # result is available
        result_address = url <> "/output"
        get_results(result_address)

      {:ok,
       %HTTPoison.Response{
         status_code: 200
       }} ->
        # validation is processing, try again later
        nb_tries |> poll_interval() |> :timer.sleep()
        poll_api_result(url, nb_tries + 1)
    end
  end

  def poll_interval(nb_tries) when nb_tries < 5, do: 2_000
  def poll_interval(nb_tries) when nb_tries < 10, do: 5_000
  def poll_interval(_), do: 20_000

  def get_results(result_address) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    with {:ok,
          %HTTPoison.Response{
            status_code: 200,
            body: body
          }} <- http_client.get(result_address),
         {:ok, validation} <- Jason.decode(body) do
      {:ok, validation}
    else
      e -> {:error, "validation is done, but there was an error fetching the results. #{inspect(e)}"}
    end
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "Validata JSON"
  def validator_version, do: "0.1.0"
end
