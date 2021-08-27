defmodule DB.Resource.Validator do
  alias DB.Resource

  @doc """
  Behavior for validating a resource
  """
  @callback validate(%Resource{}) :: {:ok, %{}} | {:error, binary()}
end

defmodule DB.Resource.GtfsTransportValidator.Wrapper do
  def impl(), do: Application.get_env(:transport, :gtfs_transport_validator, DB.Resource.GtfsTransportValidator)
end

defmodule DB.Resource.Validator.Common do
  defmacro __using__([]) do
    quote do
      def validate(%DB.Resource{url: nil}) do
        {:error, "No Resource url provided"}
      end
    end
  end
end

defmodule DB.Resource.GtfsTransportValidator do
  @moduledoc """
    Validator of GTFS files, based on the Rust Validator maintened by the team
    https://github.com/etalab/transport-validator/
  """

  @behaviour DB.Resource.Validator
  use DB.Resource.Validator.Common
  alias DB.Resource

  @httpClient Transport.Shared.Wrapper.HTTPoison.impl()
  @httpRes HTTPoison.Response
  @httpErr HTTPoison.Error
  @timeout 180_000

  @doc """
    Endpoint of the gtfs validator
  """
  @spec endpoint() :: binary()
  def endpoint, do: Application.fetch_env!(:transport, :gtfs_validator_url) <> "/validate"

  @impl DB.Resource.Validator
  def validate(%Resource{format: "GTFS", url: url}) do
    case @httpClient.get("#{endpoint()}?url=#{URI.encode_www_form(url)}", [], recv_timeout: @timeout) do
      {:ok, %@httpRes{status_code: 200, body: body}} -> Jason.decode(body)
      {:ok, %@httpRes{body: body}} -> {:error, body}
      {:error, %@httpErr{reason: error}} -> {:error, error}
      _ -> {:error, "Unknown error in #{__MODULE__} validation"}
    end
  end

  def validate(%Resource{}), do: {:error, "#{__MODULE__} can only validate GTFS resources"}
end
