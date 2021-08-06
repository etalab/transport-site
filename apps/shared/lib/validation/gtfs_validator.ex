defmodule Shared.Validation.GtfsValidator do
  @moduledoc """
  GTFS validation module.
  Generate validation report when validation is done.

  Actually validation is delegated to an external service called via HTTP.
  """
  require Logger

  @timeout 180_000
  @url_property_not_set_error "Property gtfs_validator_url is not set. Set it and restart server"

  @doc """
  Validate a given GTFS file.
  GTFS must be a zip file as binary.

  Return {:ok, validation_report} if validation succeed with or without errors.
  Return {:error} if validation cannot be done.
  """
  @spec validate(binary()) :: {:ok, map()}
  def validate(gtfs), do:
    build_validate_url()
    |> send_post_request(gtfs)
    |> handle_validation_response()

  @spec validate_from_url(binary()) :: {:ok, map()} | {:error, binary()}
  def validate_from_url(gtfs_url), do:
    build_validate_url()
    |> (&(&1 <> "?url=#{URI.encode_www_form(gtfs_url)}")).()
    |> send_get_request()
    |> handle_validation_response()

  defp build_validate_url, do: gtfs_validator_base_url() <> "/validate"

  defp gtfs_validator_base_url() do
    case Application.fetch_env(:transport, :gtfs_validator_url) do
      {:ok, url} -> url
      _ -> raise @url_property_not_set_error
    end
  end

  defp handle_validation_response({:ok, %{status_code: 200, body: body}}) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        {:ok, decoded}
      {:error, error} ->
        Logger.error(error)
        {:error, "Error while decoding GTFS validator response"}
    end
  end

  defp handle_validation_response({_, %{body: body}}) do
    Logger.error(body)
    {:error, "Error while requesting GTFS validator"}
  end

  defp http_client(), do: Application.fetch_env!(:transport, :httpoison_impl)

  defp send_get_request(url), do:
    http_client().get(url, [], recv_timeout: @timeout)

  defp send_post_request(url, body), do:
    http_client().post(url, body, [], recv_timeout: @timeout)

end
