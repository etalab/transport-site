defmodule Shared.Validation.GBFSValidator do
  @moduledoc """
  A module to validate GBFS feeds
  """

  defmodule Summary do
    @moduledoc """
    A structure holding validation results for a GBFS feed
    """
    defstruct has_errors: nil, errors_count: nil, version_detected: nil, version_validated: nil

    @type t :: %__MODULE__{
            has_errors: boolean,
            errors_count: integer,
            version_detected: term,
            version_validated: term
          }
  end

  defmodule Wrapper do
    @moduledoc """
    This behaviour defines the API for a GBFS Validator
    """
    defp impl, do: Application.get_env(:transport, :gbfs_validator_impl, Shared.Validation.GBFSValidator.HTTPClient)

    @callback validate(binary()) :: {:ok, Summary.t()} | {:error, binary()}
    def validate(url), do: impl().validate(url)
  end

  defmodule HTTPClient do
    @moduledoc """
    An HTTP GBFS Validator calling a third party API
    """
    @behaviour Wrapper
    require Logger
    @validator_url "https://gbfs-validator.netlify.app/.netlify/functions/validator"

    def validate(url) do
      with {:ok, %{status_code: 200, body: response}} <- call_api(url),
           {:ok, json} <- Jason.decode(response) do
        {:ok,
         %Summary{
           has_errors: json["summary"]["hasErrors"],
           errors_count: json["summary"]["errorsCount"],
           version_detected: json["summary"]["version"]["detected"],
           version_validated: json["summary"]["version"]["validated"]
         }}
      else
        e ->
          message = "impossible to query GBFS Validator: #{inspect(e)}"
          Logger.error(message)
          {:error, message}
      end
    end

    defp http_client, do: Application.fetch_env!(:transport, :httpoison_impl)

    defp call_api(url) do
      body = Jason.encode!(%{url: url})
      headers = [{"content-type", "application/json"}, {"user-agent", Application.get_env(:transport, :contact_email)}]
      http_client().post(@validator_url, body, headers)
    end
  end
end
