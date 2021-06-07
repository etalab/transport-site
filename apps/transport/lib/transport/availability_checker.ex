defmodule Transport.AvailabilityChecker do
  @moduledoc """
  A module used to check if a remote file is "available" through a GET a request.
  Gives a response even if remote server does not support HEAD requests (405 response)
  """

  @spec available?(map() | binary()) :: boolean
  def available?(target, use_stream_method \\ false)

  def available?(%{"url" => url}, use_stream_method), do: available?(url, use_stream_method)

  def available?(url, false) when is_binary(url) do
    case HTTPoison.head(url, [], follow_redirect: true) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> true
      {:ok, %HTTPoison.Response{status_code: 405}} -> available?(url, _use_stream_method = true)
      _ -> false
    end
  end

  def available?(url, _use_stream_method = true) do
    case HTTPStreamV2.fetch_status_follow_redirect(url) do
      {:ok, 200} -> true
      _ -> false
    end
  end
end
