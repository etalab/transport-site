defmodule Hasher do
  @moduledoc """
  Hasher computes the hash sha256 of file given by the URL
  """
  require Logger

  @spec get_content_hash(String.t()) :: String.t()
  def get_content_hash(url) do
    case scheme = URI.parse(url).scheme do
      s when s in ["http", "https"] ->
        get_content_hash_http(url)

      _ ->
        Logger.warn("Cannot process #{scheme |> inspect} url (#{url}) at the moment. Skipping.")
        nil
    end
  end

  @spec get_content_hash_http(String.t()) :: String.t()
  def get_content_hash_http(url) do
    # SSL config is a temporary fix for https://github.com/etalab/transport-site/issues/1564
    # The better fix is to add proper tests around that and upgrade to OTP 23.
    with {:ok, %{headers: headers}} <- HTTPoison.head(url, [], ssl: [versions: [:"tlsv1.2"]]),
         etag when not is_nil(etag) <- Enum.find_value(headers, &find_etag/1),
         content_hash <- String.replace(etag, "\"", "") do
      content_hash
    else
      {:error, error} ->
        Logger.error(fn -> "error while computing content_hash #{inspect(error)}" end)
        nil

      nil ->
        compute_sha256(url)
    end
  end

  @spec compute_sha256(String.t()) :: String.t()
  def compute_sha256(url) do
    url
    |> HTTPStream.get()
    |> Enum.reduce(:crypto.hash_init(:sha256), &update_hash/2)
    |> case do
      :error ->
        Logger.debug(fn -> "Unable to compute hash for #{url}" end)
        ""

      hash ->
        hash
        |> :crypto.hash_final()
        |> Base.encode16()
        |> String.downcase()
    end
  end

  @spec update_hash(binary(), binary() | :error) :: binary() | :error
  defp update_hash(_, :error), do: :error
  defp update_hash(chunk, hash), do: :crypto.hash_update(hash, chunk)

  @spec find_etag(keyword()) :: binary()
  defp find_etag({"Etag", v}), do: v
  defp find_etag(_), do: nil
end
