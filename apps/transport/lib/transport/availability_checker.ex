defmodule Transport.AvailabilityChecker.Wrapper do
  @moduledoc """
  Defines a behavior
  """

  @callback available?(map() | binary()) :: boolean
  def impl, do: Application.get_env(:transport, :availability_checker_impl)
  def available?(x), do: impl().available?(x)
end

defmodule Transport.AvailabilityChecker.Dummy do
  @moduledoc """
  A dummy module where everything is always available
  """
  @behaviour Transport.AvailabilityChecker.Wrapper

  @impl Transport.AvailabilityChecker.Wrapper
  def available?(_), do: true
end

defmodule Transport.AvailabilityChecker do
  @moduledoc """
  A module used to check if a remote file is "available" through a GET a request.
  Gives a response even if remote server does not support HEAD requests (405 response)
  """
  alias HTTPoison.Response

  @behaviour Transport.AvailabilityChecker.Wrapper

  @impl Transport.AvailabilityChecker.Wrapper
  @spec available?(map() | binary()) :: boolean
  def available?(target, use_http_streaming \\ false)

  def available?(%{"url" => url}, use_http_streaming), do: available?(url, use_http_streaming)

  def available?(url, false) when is_binary(url) do
    case HTTPoison.head(url, [], follow_redirect: true) do
      {:ok, %Response{status_code: code}} when code >= 200 and code < 300 -> true
      {:ok, %Response{status_code: code}} when code in [401, 403, 405] -> available?(url, _use_http_streaming = true)
      _ -> false
    end
  end

  def available?(url, true = _use_http_streaming) do
    case HTTPStreamV2.fetch_status_follow_redirect(url) do
      {:ok, 200} -> true
      _ -> false
    end
  end
end
