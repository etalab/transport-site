defmodule HTTPStreamV2 do
  @moduledoc """
  A new module able to compute checksum of a given URL via streaming, all
  while retaining extra information such as HTTP status, body size, and headers.
  """

  @doc """
  Issue a streamed GET request, computing the SHA256 of the payload on the fly,
  and returning the result as a map:

  ```
  %{
    status: 200,
    hash: "95ab5b2602d6a21d7efcbc87de641c59f2ecc7510a1aa0d20708f122faf172ca",
    headers: [...],
    body_byte_size: 123456
  }
  ```

  The headers are kept around for a variety of reasons. We could use them to follow a redirect,
  double-check the etag, verify the content type etc.
  """

  # same as HTTPoison
  @redirect_status [301, 302, 307]
  @default_allowed_redirects 5

  @spec fetch_status_and_hash(binary(), integer(), integer()) :: {:ok, map()} | {:error, any()}
  def fetch_status_and_hash(url, max_redirect \\ @default_allowed_redirects, redirect_count \\ 0)

  def fetch_status_and_hash(_url, max_redirect, redirect_count)
      when redirect_count > max_redirect do
    {:error, "maximum number of redirect reached"}
  end

  def fetch_status_and_hash(url, max_redirect, redirect_count) do
    request = Finch.build(:get, URI.encode(url))

    try do
      {:ok, result} = Finch.stream(request, Transport.Finch, %{}, &handle_stream_response/2)
      {:ok, compute_final_hash(result)}
    catch
      {:redirect, redirect_url} ->
        fetch_status_and_hash(redirect_url, max_redirect, redirect_count + 1)

      {:error, e} ->
        {:error, e}
    end
  end

  defp handle_stream_response({:status, status}, acc) do
    acc
    |> Map.put(:status, status)
    |> Map.put(:hash, :crypto.hash_init(:sha256))
    |> Map.put(:body_byte_size, 0)
  end

  defp handle_stream_response({:headers, headers}, acc) do
    case acc.status do
      status when status in @redirect_status ->
        headers
        |> location_header()
        |> case do
          nil -> throw({:error, "no redirection url provided"})
          {_, redirect_url} -> throw({:redirect, redirect_url})
        end

      _ ->
        acc |> Map.put(:headers, headers)
    end
  end

  defp handle_stream_response({:data, data}, acc) do
    hash = :crypto.hash_update(acc.hash, data)
    %{acc | hash: hash, body_byte_size: acc[:body_byte_size] + (data |> byte_size)}
  end

  defp compute_final_hash(result) do
    hash =
      result
      |> Map.fetch!(:hash)
      |> :crypto.hash_final()
      |> Base.encode16()
      |> String.downcase()

    %{result | hash: hash}
  end

  @spec fetch_status(binary()) :: {:ok, map()} | {:error, any()}
  def fetch_status(url) do
    request = Finch.build(:get, URI.encode(url))
    Finch.stream(request, Transport.Finch, %{}, &handle_stream_status/2)
  catch
    # when status is fetched, a throw is used to stop the streaming and exit with the needed information
    {:status_fetched, status} -> status
    e -> {:error, e}
  end

  defp location_header(headers) do
    headers |> Enum.find(fn {k, _v} -> String.downcase(k) == "location" end)
  end

  defp handle_stream_status({:status, status}, acc) do
    acc = acc |> Map.put(:status, status)

    if status not in @redirect_status do
      # we know everything we need to know
      throw({:status_fetched, {:ok, acc}})
    end

    acc
  end

  defp handle_stream_status({:headers, headers}, acc) do
    acc =
      headers
      |> location_header()
      |> case do
        nil -> acc
        {_, url} -> acc |> Map.put(:location, url)
      end

    throw({:status_fetched, {:ok, acc}})
  end

  def fetch_status_follow_redirect(
        url,
        max_redirect \\ @default_allowed_redirects,
        redirect_count \\ 0
      )

  def fetch_status_follow_redirect(_url, max_redirect, redirect_count)
      when redirect_count > max_redirect do
    {:error, "maximum number of redirect reached"}
  end

  def fetch_status_follow_redirect(url, max_redirect, redirect_count) do
    case fetch_status(url) do
      {:ok, %{status: status, location: redirect_url}} when status in @redirect_status ->
        fetch_status_follow_redirect(redirect_url, max_redirect, redirect_count + 1)

      {:ok, %{status: status}} ->
        {:ok, status}

      _ ->
        {:error, "error while fetching status"}
    end
  end
end
