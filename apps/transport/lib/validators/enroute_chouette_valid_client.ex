defmodule Transport.EnRouteChouetteValidClient.Wrapper do
  @moduledoc """
  A client for the enRoute Chouette Valid API.
  Documentation: https://documenter.getpostman.com/view/9950294/2sA3e2gVEE
  """

  @callback create_a_validation(Path.t()) :: binary()
  @callback get_a_validation(binary()) ::
              :pending
              | {:successful, binary(), integer()}
              | {:warning, integer()}
              | {:failed, integer()}
              | :unexpected_validation_status
  @callback get_messages(binary()) :: {binary(), map()}

  def impl, do: Application.get_env(:transport, :enroute_validator_client)
end

defmodule Transport.EnRouteChouetteValidClient do
  @moduledoc """
  Implementation of the enRoute Chouette Valid API client.
  """
  @behaviour Transport.EnRouteChouetteValidClient.Wrapper

  @base_url "https://chouette-valid.enroute.mobi/api/validations"

  @impl Transport.EnRouteChouetteValidClient.Wrapper
  def create_a_validation(filepath) do
    form =
      {:multipart,
       [
         {"validation[rule_set]", "enroute:starter-kit"},
         {"validation[include_schema]", "true"},
         make_file_part("validation[file]", filepath)
       ]}

    %HTTPoison.Response{status_code: 201, body: body} = http_client().post!(@base_url, form, auth_headers())
    body |> Jason.decode!() |> Map.fetch!("id")
  end

  @impl Transport.EnRouteChouetteValidClient.Wrapper
  def get_a_validation(validation_id) do
    url = validation_url(validation_id)

    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, auth_headers())

    response = body |> Jason.decode!()

    case response |> Map.fetch!("user_status") do
      "pending" ->
        :pending

      "successful" ->
        {:successful, url, get_elapsed!(response)}

      "warning" ->
        {:warning, get_elapsed!(response)}

      "failed" ->
        {:failed, get_elapsed!(response)}

      _ ->
        :unexpected_validation_status
    end
  end

  defp get_elapsed!(response) do
    created_at = get_datetime!(response, "started_at")
    updated_at = get_datetime!(response, "ended_at")
    DateTime.diff(updated_at, created_at)
  end

  defp get_datetime!(map, key) do
    raw_date = Map.fetch!(map, key)

    case DateTime.from_iso8601(raw_date) do
      {:ok, value, _offset} ->
        value

      {:error, reason} ->
        raise ArgumentError, "cannot parse #{inspect(raw_date)} as datetime, reasaon: #{inspect(reason)}"
    end
  end

  @impl Transport.EnRouteChouetteValidClient.Wrapper
  def get_messages(validation_id) do
    url = Path.join([validation_url(validation_id), "messages"])

    %HTTPoison.Response{status_code: 200, body: body} = http_client().get!(url, auth_headers())
    {url, body |> Jason.decode!()}
  end

  defp make_file_part(field_name, filepath) do
    {:file, filepath, {"form-data", [{:name, field_name}, {:filename, Path.basename(filepath)}]}, []}
  end

  defp validation_url(validation_id) do
    Path.join([@base_url, validation_id])
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()

  defp auth_headers do
    [{"authorization", "Token token=#{Application.fetch_env!(:transport, :enroute_validation_token)}"}]
  end
end
