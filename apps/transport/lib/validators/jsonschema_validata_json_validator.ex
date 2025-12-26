defmodule Transport.Validators.ValidataJson do
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
    schema_url = Transport.Schemas.schema_url(schema_name, schema_version)

    {:ok, validation} = perform_validation(schema_url, url)

    %DB.MultiValidation{
      validation_timestamp: DateTime.utc_now(),
      validator: validator_name(),
      result: validation,
      digest: digest(validation),
      resource_history_id: resource_history_id,
      validator_version: validator_version(),
      command: validation_url(schema_url, url)
    }
    |> DB.Repo.insert!()

    :ok
  end

  @spec base_url :: URI.t()
  def base_url, do: "https://json.validator.validata.fr" |> URI.new!()

  @doc """
  build the validation url

  iex> validation_url("sss", "ddd")
  "https://json.validator.validata.fr/url_validation_job?data=ddd&schema=sss"
  """
  def validation_url(schema_url, data_url) do
    base_url()
    |> URI.merge("/url_validation_job")
    |> URI.append_query(URI.encode_query(data: data_url, schema: schema_url))
    |> URI.to_string()
  end

  def poll_url(job_id),
    do: base_url() |> URI.merge("/job/#{job_id}") |> URI.to_string()

  def perform_validation(schema_url, url) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    validation_url = validation_url(schema_url, url)

    case http_client.post(validation_url, "") do
      {:ok, %HTTPoison.Response{status_code: 201, body: job_id}} ->
        job_id |> String.replace("\"", "") |> get_api_result()

      _ ->
        {:error, "validation server error, job creation failed"}
    end
  end

  def get_api_result(job_id) do
    job_id |> poll_url() |> poll_api_result(0)
  end

  def poll_api_result(_url, nb_tries) when nb_tries > 30 do
    {:error, "validation timeout, too many polling attempts"}
  end

  def poll_api_result(url, nb_tries) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    case http_client.get(url) do
      {:ok, %HTTPoison.Response{status_code: 303, headers: headers}} ->
        # result is available
        [location] = Transport.Http.Utils.location_header(headers)

        base_url()
        |> Map.put(:path, location)
        # get a json validation report
        |> URI.append_query(URI.encode_query(text_or_json: "json"))
        |> URI.to_string()
        |> get_results()

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        if body =~ "FAILURE" do
          {:error, "validation failure"}
        else
          # validation is processing, try again later
          nb_tries |> poll_interval() |> :timer.sleep()
          poll_api_result(url, nb_tries + 1)
        end
    end
  end

  def poll_interval(nb_tries) when nb_tries < 5, do: 2_000
  def poll_interval(nb_tries) when nb_tries < 10, do: 5_000
  def poll_interval(_), do: 20_000

  def get_results(result_address) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- http_client.get(result_address),
         {:ok, validation} <- Jason.decode(body) do
      {:ok, validation}
    else
      e ->
        {:error, "validation is done, but there was an error fetching the results. #{inspect(e)}"}
    end
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "Validata JSON"
  def validator_version, do: "0.1.0"

  @doc """
  iex> digest(%{"warnings_count" => 2, "errors_count" => 3, "issues" => []})
  %{"errors_count" => 3, "warnings_count" => 2}
  iex> digest(%{"issues" => []})
  %{}
  """
  def digest(validation_result) do
    Map.intersect(%{"warnings_count" => 0, "errors_count" => 0}, validation_result)
  end
end
