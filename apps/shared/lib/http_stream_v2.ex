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
    hash = result
    |> Map.fetch!(:hash)
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()

    %{result | hash: hash}
  end

  def fetch_status(url) do
    try do
      request = Finch.build(:get, url)
      Finch.stream(request, Transport.Finch, %{}, &handle_stream_status/2)
    catch
      status -> status
    end
  end

  defp handle_stream_status(tuple, acc) do
    case tuple do
      {:status, status} when status in [301,302] ->
        acc
        |> Map.put(:status, status)

      {:status, status} ->
        throw({:ok, acc |> Map.put(:status, status)})

      {:headers, headers} ->
        location_header = headers |> Enum.find(fn {k, _v} -> k in ["Location", "location"] end)

        case location_header do
          nil -> acc
          {_, url} -> acc |> Map.put(:location, url)
        end

      {:data, _data} ->
        case acc do
          {:ok, %{status: _, location: _}} -> throw(acc)
          {:ok, %{status: status}} when status not in [301, 302] -> throw(acc)
          _ -> acc
        end
    end
  end

  def fetch_status_follow_redirect(url, redirect_count \\ 0, max_redirect \\ 10)

  def fetch_status_follow_redirect(_url, redirect_count, max_redirect)
      when redirect_count > max_redirect do
    {:error, "maximum number of redirect reached"}
  end

  def fetch_status_follow_redirect(url, redirect_count, max_redirect) do
    case fetch_status(url) do
      {:ok, %{status: status, location: redirect_url}} when status in [301, 302] ->
        fetch_status_follow_redirect(redirect_url, redirect_count + 1, max_redirect)

      {:ok, %{status: status}} ->
        status

      _ ->
        {:error, "error while fetching status"}
    end
  end
end
