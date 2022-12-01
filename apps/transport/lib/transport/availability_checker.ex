defmodule Transport.AvailabilityChecker.Wrapper do
  @moduledoc """
  Defines a behavior
  """

  @callback available?(binary(), binary()) :: boolean
  def impl, do: Application.get_env(:transport, :availability_checker_impl)
  def available?(resource_format, url), do: impl().available?(resource_format, url)
end

defmodule Transport.AvailabilityChecker.Dummy do
  @moduledoc """
  A dummy module where everything is always available
  """
  @behaviour Transport.AvailabilityChecker.Wrapper

  @impl Transport.AvailabilityChecker.Wrapper
  def available?(_, _), do: true
end

defmodule Transport.AvailabilityChecker do
  @moduledoc """
  A module used to check if a remote file is "available" through a GET a request.
  Gives a response even if remote server does not support HEAD requests (405 response)
  """
  alias HTTPoison.Response

  @behaviour Transport.AvailabilityChecker.Wrapper

  @impl Transport.AvailabilityChecker.Wrapper
  @spec available?(binary(), binary()) :: boolean
  def available?(format, target, use_http_streaming \\ false)

  def available?("SIRI", url, _) when is_binary(url) do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %Response{status_code: code}} when (code >= 200 and code < 300) or code == 401 ->
        true

      _ ->
        false
    end
  end

  def available?(format, url, false) when is_binary(url) do
    case http_client().head(url, [], follow_redirect: true) do
      {:ok, %Response{status_code: code}} when code >= 200 and code < 300 ->
        true

      {:ok, %Response{status_code: code}} when code in [401, 403, 405] ->
        available?(format, url, _use_http_streaming = true)

      _ ->
        false
    end
  end

  def available?(_format, url, true = _use_http_streaming) do
    case HTTPStreamV2.fetch_status_follow_redirect(url) do
      {:ok, 200} -> true
      _ -> false
    end
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
