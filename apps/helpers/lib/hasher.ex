defmodule Hasher do
    @moduledoc """
    Hasher computes the hash sha256 of file given by the URL
    """
    require Logger

    @spec get_content_hash(String.t) :: String.t
    def get_content_hash(url) do
        with {:ok, %{headers: headers}} <- HTTPoison.head(url),
             etag when not is_nil(etag) <- Enum.find_value(headers, &find_etag/1),
             content_hash <- String.replace(etag, "\"", "") do

            content_hash
        else
            {:error, error} ->
                Logger.error fn -> inspect error end
                nil
            nil ->
                compute_sha256(url)
        end
    end

    @spec compute_sha256(String.t) :: String.t
    def compute_sha256(url) do
        url
        |> HTTPStream.get()
        |> Enum.reduce(:crypto.hash_init(:sha256), &update_hash/2)
        |> case do
            :error ->
                Logger.debug fn -> "Unable to compute hash for #{url}" end
                ""
            hash ->
                hash
                |> :crypto.hash_final()
                |> Base.encode16()
                |> String.downcase()
        end
    end

    defp update_hash(_, :error), do: :error
    defp update_hash(:error, _), do: :error
    defp update_hash(chunk, hash) when is_binary(chunk), do: :crypto.hash_update(hash, chunk)
    defp update_hash(_, _), do: :error

    defp find_etag({"Etag", v}), do: v
    defp find_etag(_), do: nil
end
