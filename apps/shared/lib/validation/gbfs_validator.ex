defmodule Shared.Validation.GBFSValidator do
  @moduledoc """
  A module to validate GBFS feeds
  """

  defmodule Summary do
    @moduledoc """
    A structure holding validation results for a GBFS feed
    """
    @enforce_keys [:has_errors, :errors_count, :version_detected, :version_validated, :validator_version, :validator]
    @derive Jason.Encoder
    defstruct has_errors: false,
              errors_count: nil,
              version_detected: nil,
              version_validated: nil,
              validator_version: nil,
              validator: nil

    @type t :: %__MODULE__{
            has_errors: boolean,
            errors_count: integer,
            version_detected: binary,
            version_validated: binary,
            validator_version: binary,
            validator: module
          }
  end

  defmodule Wrapper do
    @moduledoc """
    This behaviour defines the API for a GBFS Validator
    """
    defp impl, do: Application.get_env(:transport, :gbfs_validator_impl)

    @callback validate(binary()) :: {:ok, Summary.t()} | {:error, binary()}
    def validate(url), do: impl().validate(url)
  end

  defmodule HTTPValidatorClient do
    @moduledoc """
    An HTTP GBFS Validator calling a third party API
    """
    @behaviour Wrapper
    require Logger

    def validate(url) do
      with {:ok, %{status_code: 200, body: response}} <- call_api(url),
           {:ok, json} <- Jason.decode(response) do
        {:ok,
         %Summary{
           has_errors: json["summary"]["hasErrors"],
           errors_count: json["summary"]["errorsCount"],
           version_detected: json["summary"]["version"]["detected"],
           version_validated: json["summary"]["version"]["validated"],
           validator_version: json["summary"]["validatorVersion"],
           validator: __MODULE__
         }}
      else
        e ->
          message = "impossible to query GBFS Validator: #{inspect(e)}"
          Logger.error(message)
          {:error, message}
      end
    end

    defp validator_url, do: Application.fetch_env!(:transport, :gbfs_validator_url)

    defp call_api(url) do
      body = Jason.encode!(%{url: url})
      headers = [{"content-type", "application/json"}, {"user-agent", Application.get_env(:transport, :contact_email)}]

      Transport.Shared.Wrapper.HTTPoison.impl().post(validator_url(), body, headers)
    end
  end
end
