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

  def available?(format, url, _) when is_binary(url) and format in ["SIRI", "SIRI Lite"] do
    case http_client().get(url, [], follow_redirect: true) do
      {:ok, %Response{status_code: code}} when (code >= 200 and code < 300) or code in [401, 405] ->
        true

      # Bug affecting Hackney (dependency of HTTPoison)
      # 303 status codes on `GET` requests should be fine but they're returned as errors
      # https://github.com/edgurgel/httpoison/issues/171#issuecomment-244029927
      # https://github.com/etalab/transport-site/issues/3463
      {:error, %HTTPoison.Error{reason: {:invalid_redirection, _}}} ->
        # NOTE: this does not actually verifies that the target is available at the moment!
        true

      _ ->
        false
    end
  end

  def available?(format, url, false) when is_binary(url) do
    options = [follow_redirect: true]
    # Hot-fix for https://github.com/etalab/transport-site/issues/4122
    # Least intrusive fix, only pass `force_redirection` to `HTTPoison` if the param value is true, else
    # do not specify it, to avoid side-effect.
    # See: https://github.com/benoitc/hackney/blob/eca5fbb1ff2d84facefb2a633e00f6ca16e7ddfd/src/hackney_stream.erl#L173
    # Google Drive content (1 instance at time of writing) returns a 303, and by default `hackney` only allows
    # POST method for this, but here HEAD/GET are supported and required. By using `force_redirection` in `hackney`
    # options, this indicated `hackney` that the redirect should still occur.
    options =
      if URI.parse(url).host == "drive.google.com" do
        options |> Keyword.merge(hackney: [force_redirect: true])
      else
        options
      end

    case http_client().head(url, [], options) do
      # See https://developer.mozilla.org/en-US/docs/Web/HTTP/Status#successful_responses
      # Other 2xx status codes don't seem appropriate here
      {:ok, %Response{status_code: 200}} ->
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
