defmodule Hasher.Wrapper do
  @moduledoc """
  A Hasher wrapper, useful for testing purposes
  """

  @callback get_content_hash(binary()) :: binary()
  def impl, do: Application.get_env(:transport, :hasher_impl)
end

defmodule Hasher.Dummy do
  @moduledoc """
  A dummy module, where everything always has the same dummy hash
  """
  @behaviour Hasher.Wrapper

  @impl Hasher.Wrapper
  def get_content_hash(_url), do: "xxx"
end

defmodule Hasher do
  @moduledoc """
  Hasher computes the hash sha256 of a file given by
  an URL or a local path
  """
  require Logger
  @behaviour Hasher.Wrapper

  @impl Hasher.Wrapper
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
    case HTTPStreamV2.fetch_status_and_hash(url) do
      {:ok, %{status: 200, hash: hash}} ->
        hash

      {:error, msg} ->
        Logger.warn("Cannot compute hash for url #{url |> inspect}, returning empty hash. Error : #{msg |> inspect}")

        # NOTE: this mimics the legacy code, and maybe we could return nil instead, but the whole
        # thing isn't under tests, so I prefer to keep it like before for now.
        ""
    end
  rescue
    e ->
      Logger.error(
        "Exception #{e |> inspect} occurred during hash computation for url #{url |> inspect}, returning empty hash"
      )

      ""
  end

  @spec find_etag(keyword()) :: binary()
  defp find_etag({"Etag", v}), do: v
  defp find_etag(_), do: nil

  def compute_checksum(stream, algorithm) do
    stream
    |> Enum.reduce(:crypto.hash_init(algorithm), fn elm, acc -> :crypto.hash_update(acc, elm) end)
    |> :crypto.hash_final()
    |> Base.encode16()
    |> String.downcase()
  end

  def get_file_hash(file_path) do
    file_path
    |> File.stream!([], 2048)
    |> compute_checksum(:sha256)
  end

  @doc """
  Computes a single sha256 string using a ZIP metadata payload.

  ZIP metadata is produced by `Transport.ZipMetaDataExtractor.extract!/1`.

  iex> zip_hash([%{"compressed_size" => 41, "file_name" => "ExportService.checksum.md5", "last_modified_datetime" => "2017-02-16T05:01:12", "sha256" => "f0c7216411dec821330ffbebf939bfe73a50707f5e443795a122ec7bef37aa16", "uncompressed_size" => 47}, %{"compressed_size" => 115, "file_name" => "agency.txt", "last_modified_datetime" => "2017-02-16T05:01:12", "sha256" => "548de694a86ab7d6ac0cd3535b0c3b8bffbabcc818e8d7f5a4b8f17030adf617", "uncompressed_size" => 143}])
  "ddb5bc46003dbe71c98edcbbd4d5c6e9a101b8727a749a84ac4e777fd2302732"
  """
  def zip_hash(zip_metadata) when is_list(zip_metadata) do
    zip_metadata
    |> Enum.sort_by(&get_signature(&1))
    |> Stream.map(&get_signature(&1))
    |> compute_checksum(:sha256)
  end

  @doc """
  Computes the signature of a ZIP metadata item.
  We concatenate the filename and its sha256 together.

  Using the sha256 alone is not enough because the ZIP archive hash
  would be the same when renaming files without changing their content.

  iex> get_signature(%{"compressed_size" => 41, "file_name" => "file.txt", "last_modified_datetime" => "2017-02-16T05:01:12", "sha256" => "f0c7216411dec821330ffbebf939bfe73a50707f5e443795a122ec7bef37aa16", "uncompressed_size" => 47})
  "file.txtf0c7216411dec821330ffbebf939bfe73a50707f5e443795a122ec7bef37aa16"
  """
  def get_signature(zip_metadata_item) when is_map(zip_metadata_item) do
    map_get(zip_metadata_item, :file_name) <> map_get(zip_metadata_item, :sha256)
  end

  defp map_get(map, key) when key in [:sha256, :file_name] do
    # At the moment zip_metadata may have atom keys (when coming from Elixir)
    # or string keys (when coming from the database).
    # Guard is here to prevent against other usages.
    Map.get(map, key) || Map.get(map, to_string(key))
  end
end
