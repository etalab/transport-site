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
  def fetch_status_and_hash(url) do
    request = Finch.build(:get, url)
    {:ok, result} = Finch.stream(request, Transport.Finch, %{}, &handle_stream_response/2)
    compute_final_hash(result)
  end

  defp handle_stream_response(tuple, acc) do
    case tuple do
      {:status, status} ->
        acc
        |> Map.put(:status, status)
        |> Map.put(:hash, :crypto.hash_init(:sha256))
        |> Map.put(:body_byte_size, 0)

      {:headers, headers} ->
        acc
        |> Map.put(:headers, headers)

      {:data, data} ->
        hash = :crypto.hash_update(acc.hash, data)
        %{acc | hash: hash, body_byte_size: acc[:body_byte_size] + (data |> byte_size)}
    end
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

  def fetch_status(url) do
    request = Finch.build(:get, url)
    Finch.stream(request, Transport.Finch, %{}, &handle_stream_status/2)
  catch
    status -> status
  end

  @redirect_status [301, 302, 307]

  defp handle_stream_status({:status, status}, acc) do
    res = acc |> Map.put(:status, status)
    if status not in @redirect_status do
      # we know everything we need to know
      throw({:ok, res})
    end
    res
  end

  defp handle_stream_status({:headers, headers}, acc) do
    location_header = headers |> Enum.find(fn {k, _v} -> k in ["Location", "location"] end)

    case location_header do
      nil -> acc
      {_, url} -> acc |> Map.put(:location, url)
    end
  end

  defp handle_stream_status({:data, _data}, acc) do
    case acc do
      {:ok, %{status: _, location: _}} -> throw(acc)
      {:ok, %{status: status}} when status not in @redirect_status -> throw(acc)
      _ -> acc
    end
  end

  # same default max_redirect as HTTPoison
  def fetch_status_follow_redirect(url, max_redirect \\ 5, redirect_count \\ 0)

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
