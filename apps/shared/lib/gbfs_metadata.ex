defmodule Transport.Shared.GBFSMetadata.Wrapper do
  @moduledoc """
  Defines a behavior
  """

  @callback compute_feed_metadata(binary(), binary()) :: map()
  def impl, do: Application.get_env(:transport, :gbfs_metadata_impl)
  def compute_feed_metadata(url, cors_base_url), do: impl().compute_feed_metadata(url, cors_base_url)
end

defmodule Transport.Shared.GBFSMetadata do
  @moduledoc """
  Compute and store metadata for GBFS resources.
  """
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary
  alias Shared.Validation.GBFSValidator.Wrapper, as: GBFSValidator
  require Logger
  @behaviour Transport.Shared.GBFSMetadata.Wrapper

  @doc """
  This function does 2 HTTP calls on a given resource url, and returns a report
  with metadata and also validation status (using a third-party HTTP validator).
  """
  @impl Transport.Shared.GBFSMetadata.Wrapper
  def compute_feed_metadata(url, cors_base_url) do
    {:ok, %{status_code: 200, body: body} = response} = http_client().get(url, [{"origin", cors_base_url}])
    {:ok, json} = Jason.decode(body)

    # we compute the feed delay before the rest for accuracy
    feed_timestamp_delay = feed_timestamp_delay(json)

    %{
      validation: validation(url),
      cors_header_value: cors_header_value(response),
      feeds: feeds(json),
      versions: versions(json),
      languages: languages(json),
      system_details: system_details(json),
      vehicle_types: vehicle_types(json),
      types: types(json),
      ttl: ttl(json),
      feed_timestamp_delay: feed_timestamp_delay
    }
  rescue
    e ->
      Logger.warning("Could not compute GBFS feed metadata. Reason: #{inspect(e)}")
      %{}
  end

  @spec validation(binary()) :: GBFSValidationSummary.t() | nil
  defp validation(url) do
    case GBFSValidator.validate(url) do
      {:ok, %GBFSValidationSummary{} = summary} -> summary
      {:error, _} -> nil
    end
  end

  defp types(%{"data" => _data} = payload) do
    has_bike_status = has_feed?(payload, "free_bike_status")
    has_station_information = has_feed?(payload, "station_information")

    cond do
      has_bike_status and has_station_information ->
        ["free_floating", "stations"]

      has_bike_status ->
        ["free_floating"]

      has_station_information ->
        ["stations"]

      true ->
        Logger.error("Cannot detect GBFS types for feed #{inspect(payload)}")
        nil
    end
  end

  defp cors_header_value(%HTTPoison.Response{headers: headers}) do
    headers = headers |> Enum.into(%{}, fn {h, v} -> {String.downcase(h), v} end)
    Map.get(headers, "access-control-allow-origin")
  end

  defp ttl(%{"data" => _data} = payload) do
    feed_name = feed_to_use_for_ttl(types(payload))

    if is_nil(feed_name) do
      feed_ttl(payload["ttl"])
    else
      payload |> first_feed() |> feed_url_by_name(feed_name) |> feed_ttl()
    end
  end

  defp feed_ttl(value) when is_integer(value) and value >= 0, do: value

  defp feed_ttl(feed_url) when is_binary(feed_url) do
    with {:ok, %{status_code: 200, body: body}} <- http_client().get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      json["ttl"]
    else
      e ->
        Logger.error("Cannot get GBFS ttl details: #{inspect(e)}")
        nil
    end
  end

  @doc """
  Computes the freshness in seconds of a feed's content

  iex> last_updated = DateTime.utc_now() |> DateTime.add(-1, :minute)
  iex> delay = feed_timestamp_delay(%{"last_updated" => last_updated |> DateTime.to_unix()})
  iex> delay >= 60 and delay <= 62
  true
  iex> delay = feed_timestamp_delay(%{"last_updated" => last_updated |> DateTime.to_iso8601()})
  iex> delay >= 60 and delay <= 62
  true
  iex> feed_timestamp_delay(%{"x" => 1})
  nil
  iex> feed_timestamp_delay(%{"last_updated" => "F6"})
  nil
  """
  @spec feed_timestamp_delay(any()) :: nil | integer
  def feed_timestamp_delay(%{"last_updated" => last_updated}) when is_integer(last_updated) do
    last_updated
    |> DateTime.from_unix()
    |> case do
      {:ok, %DateTime{} = dt} -> DateTime.utc_now() |> DateTime.diff(dt)
      _ -> nil
    end
  end

  def feed_timestamp_delay(%{"last_updated" => last_updated}) when is_binary(last_updated) do
    case DateTime.from_iso8601(last_updated) do
      {:ok, %DateTime{} = utc_datetime, _} -> DateTime.utc_now() |> DateTime.diff(utc_datetime)
      _ -> nil
    end
  end

  def feed_timestamp_delay(_), do: nil

  @doc """
  Determines the feed to use as the ttl value of a GBFS feed.

  iex> Transport.Shared.GBFSMetadata.feed_to_use_for_ttl(["free_floating", "stations"])
  "free_bike_status"

  iex> Transport.Shared.GBFSMetadata.feed_to_use_for_ttl(["stations"])
  "station_information"

  iex> Transport.Shared.GBFSMetadata.feed_to_use_for_ttl(nil)
  nil
  """
  def feed_to_use_for_ttl(types) do
    case types do
      ["free_floating", "stations"] -> "free_bike_status"
      ["free_floating"] -> "free_bike_status"
      ["stations"] -> "station_information"
      nil -> nil
    end
  end

  defp system_details(%{"data" => _data} = payload) do
    feed_url = payload |> first_feed() |> feed_url_by_name("system_information")

    if not is_nil(feed_url) do
      with {:ok, %{status_code: 200, body: body}} <- http_client().get(feed_url),
           {:ok, json} <- Jason.decode(body) do
        %{
          timezone: json["data"]["timezone"],
          name: json["data"]["name"]
        }
      else
        e ->
          Logger.error("Cannot get GBFS system_information details: #{inspect(e)}")
          nil
      end
    end
  end

  def first_feed(%{"data" => data, "version" => version} = payload) do
    # From GBFS 1.1 until GBFS 2.3
    if String.starts_with?(version, ["1.", "2."]) do
      first_language = payload |> languages() |> Enum.at(0)
      (data["en"] || data["fr"] || data[first_language])["feeds"]
      # From GBFS 3.0 onwards
    else
      data["feeds"]
    end
  end

  def vehicle_types(%{"data" => _data} = payload) do
    feed_url = payload |> first_feed() |> feed_url_by_name("vehicle_types")

    if is_nil(feed_url) do
      # https://gbfs.org/specification/reference/#vehicle_typesjson
      # > If this file is not included, then all vehicles in the feed are assumed to be non-motorized bicycles.
      ["bicycle"]
    else
      with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- http_client().get(feed_url),
           {:ok, json} <- Jason.decode(body) do
        json["data"]["vehicle_types"] |> Enum.map(& &1["form_factor"]) |> Enum.uniq()
      else
        _ -> nil
      end
    end
  end

  defp languages(%{"data" => data}) do
    Map.keys(data)
  end

  @spec versions(map()) :: [binary()] | nil
  defp versions(%{"data" => _data} = payload) do
    versions_url = payload |> first_feed() |> feed_url_by_name("gbfs_versions")

    if is_nil(versions_url) do
      [Map.get(payload, "version", "1.0")]
    else
      with {:ok, %{status_code: 200, body: body}} <- http_client().get(versions_url),
           {:ok, json} <- Jason.decode(body) do
        json["data"]["versions"] |> Enum.map(fn json -> json["version"] end) |> Enum.sort(:desc)
      else
        _ -> nil
      end
    end
  end

  @spec feed_url_by_name(list(), binary()) :: binary() | nil
  def feed_url_by_name(feeds, name) do
    Enum.find(feeds, fn map -> feed_is_named?(map, name) end)["url"]
  end

  @spec feed_is_named?(map(), binary()) :: boolean()
  def feed_is_named?(map, name) do
    # Many people make the mistake of appending `.json` to feed names
    # so try to match this as well
    Enum.member?([name, "#{name}.json"], map["name"])
  end

  @spec has_feed?(map(), binary()) :: boolean()
  def has_feed?(%{"data" => _data} = payload, name) do
    Enum.member?(feeds(payload), name)
  end

  def feeds(%{"data" => _data} = payload) do
    # Remove potential ".json" at the end of feed names as people
    # often make this mistake
    payload |> first_feed() |> Enum.map(fn feed -> String.replace(feed["name"], ".json", "") end)
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
