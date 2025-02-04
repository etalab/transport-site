defmodule Transport.GBFSMetadata.Wrapper do
  @moduledoc """
  Behavior for a module in charge of computing metadata for GBFS feeds.
  """

  @callback compute_feed_metadata(binary()) :: map()
  def compute_feed_metadata(url), do: impl().compute_feed_metadata(url)

  def impl, do: Application.get_env(:transport, :gbfs_metadata_impl)
end

defmodule Transport.GBFSMetadata do
  @moduledoc """
  Computes and returns metadata for GBFS feeds.
  """
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary
  alias Shared.Validation.GBFSValidator.Wrapper, as: GBFSValidator
  require Logger
  @behaviour Transport.GBFSMetadata.Wrapper

  @type feed_name ::
          :gbfs
          | :manifest
          | :gbfs_versions
          | :system_information
          | :vehicle_types
          | :station_information
          | :station_status
          # `vehicle_status` was `free_bike_status` before v3.0
          | :vehicle_status
          | :system_hours
          | :system_calendar
          | :system_regions
          | :system_pricing_plans
          | :system_alerts
          | :geofencing_zones

  @doc """
  Compute metadata and validation status (using a third-party HTTP validator) for a GBFS feed.
  It will do multiple HTTP requests (calling GBFS sub-feeds) to compute various statistics.
  """
  @impl Transport.GBFSMetadata.Wrapper
  def compute_feed_metadata(url) do
    {:ok, %HTTPoison.Response{status_code: 200, body: body}} = cached_http_get(url)
    {:ok, json} = Jason.decode(body)

    # we compute the feed delay before the rest for accuracy
    feed_timestamp_delay = feed_timestamp_delay(json)

    %{
      validation: validation(url),
      feeds: feeds(json),
      versions: versions(json),
      languages: languages(json),
      system_details: system_details(json),
      vehicle_types: vehicle_types(json),
      types: types(json),
      ttl: ttl(json),
      stats: stats(json),
      operator: operator(url),
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

  @doc """
  iex> operator("https://api.cyclocity.fr/contracts/nantes/gbfs/gbfs.json")
  "JC Decaux"
  iex> operator("https://example.com/gbfs.json")
  "Example"
  iex> operator("https://404.fr")
  nil
  """
  def operator(url) do
    Transport.CSVDocuments.gbfs_operators()
    |> Enum.find_value(fn %{"url" => operator_url, "operator" => operator} ->
      if String.contains?(url, operator_url), do: operator
    end)
  end

  def types(%{"data" => _data} = payload) do
    has_free_floating_vehicles = has_free_floating_vehicles?(payload)
    has_stations = has_stations?(payload)

    cond do
      has_free_floating_vehicles and has_stations ->
        ["free_floating", "stations"]

      has_free_floating_vehicles ->
        ["free_floating"]

      has_stations ->
        ["stations"]

      true ->
        Logger.error("Cannot detect GBFS types for feed #{inspect(payload)}")
        nil
    end
  end

  defp has_stations?(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :station_information)

    with {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      json["data"]["stations"]
      |> Enum.reject(& &1["is_virtual_station"])
      |> Enum.count() > 0
    else
      _ -> false
    end
  end

  defp has_free_floating_vehicles?(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :vehicle_status)
    virtual_station_ids = virtual_station_ids(payload)

    with {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      (json["data"]["vehicles"] || json["data"]["bikes"])
      |> Enum.any?(fn vehicle ->
        not Map.has_key?(vehicle, "station_id") or vehicle["station_id"] in virtual_station_ids
      end)
    else
      _ -> false
    end
  end

  def virtual_station_ids(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :station_information)

    with {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      json["data"]["stations"]
      |> Enum.filter(& &1["is_virtual_station"])
      |> Enum.map(& &1["station_id"])
    else
      _ -> []
    end
  end

  defp ttl(%{"data" => _data} = payload) do
    feed_name = feed_to_use_for_ttl(types(payload))

    if is_nil(feed_name) do
      feed_ttl(payload["ttl"])
    else
      payload |> feed_url_by_name(feed_name) |> feed_ttl()
    end
  end

  defp feed_ttl(value) when is_integer(value) and value >= 0, do: value

  defp feed_ttl(feed_url) when is_binary(feed_url) do
    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
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

  iex> feed_to_use_for_ttl(["free_floating", "stations"])
  :vehicle_status
  iex> feed_to_use_for_ttl(["stations"])
  :station_information
  iex> feed_to_use_for_ttl(nil)
  nil
  """
  @spec feed_to_use_for_ttl([binary()] | nil) :: feed_name() | nil
  def feed_to_use_for_ttl(types) do
    case types do
      ["free_floating", "stations"] -> :vehicle_status
      ["free_floating"] -> :vehicle_status
      ["stations"] -> :station_information
      nil -> nil
    end
  end

  def stats(%{"data" => _data} = payload) do
    station_status_statistics(payload)
    |> Map.merge(station_information_statistics(payload))
    |> Map.merge(vehicle_statistics(payload))
    |> Map.merge(%{version: 2})
  end

  def station_status_statistics(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :station_status)

    with {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      stations = Enum.reject(json["data"]["stations"], &unrealistic_station_data?/1)

      %{
        nb_stations: Enum.count(stations),
        nb_installed_stations: Enum.count(stations, & &1["is_installed"]),
        nb_renting_stations: Enum.count(stations, & &1["is_renting"]),
        nb_returning_stations: Enum.count(stations, & &1["is_returning"]),
        nb_docks_available: stations |> Enum.map(& &1["num_docks_available"]) |> non_nil_sum(),
        nb_docks_disabled: stations |> Enum.map(& &1["num_docks_disabled"]) |> non_nil_sum(),
        nb_vehicles_available_stations: stations |> Enum.map(&vehicles_available/1) |> non_nil_sum(),
        nb_vehicles_disabled_stations: stations |> Enum.map(& &1["num_vehicles_disabled"]) |> non_nil_sum()
      }
    else
      {:feed_exists, false} ->
        %{}

      e ->
        Logger.error("Cannot get GBFS station_status details: #{inspect(e)}")
        %{}
    end
  end

  def station_information_statistics(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :station_information)

    with {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      stations = json["data"]["stations"]

      %{
        nb_virtual_stations: Enum.count(stations, & &1["is_virtual_station"])
      }
    else
      {:feed_exists, false} ->
        %{}

      e ->
        Logger.error("Cannot get GBFS station_information details: #{inspect(e)}")
        %{}
    end
  end

  def vehicle_statistics(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :vehicle_status)

    with {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      vehicles = json["data"]["vehicles"] || json["data"]["bikes"]
      nb_vehicles = Enum.count(vehicles)
      nb_docked_vehicles = Enum.count(vehicles, &Map.has_key?(&1, "station_id"))

      %{
        nb_vehicles: nb_vehicles,
        nb_disabled_vehicles: Enum.count(vehicles, & &1["is_disabled"]),
        nb_reserved_vehicles: Enum.count(vehicles, & &1["is_reserved"]),
        nb_docked_vehicles: nb_docked_vehicles,
        nb_freefloating_vehicles: nb_vehicles - nb_docked_vehicles
      }
    else
      {:feed_exists, false} ->
        %{}

      e ->
        Logger.error("Cannot get GBFS vehicle_status details: #{inspect(e)}")
        %{}
    end
  end

  @doc """
  Is the number of docks or vehicles unrealistic for this station? (more than 500 docks or vehicles).
  If yes, used to ignore this station to maintain relevant statistics.

  iex> unrealistic_station_data?(%{"num_vehicles_available" => 1_000})
  true
  iex> unrealistic_station_data?(%{"num_docks_available" => 1_000})
  true
  iex> unrealistic_station_data?(%{"num_docks_available" => 20, "num_vehicles_available" => 10})
  false
  """
  def unrealistic_station_data?(%{} = data) do
    data
    |> Map.take(["num_vehicles_available", "num_bikes_available", "num_docks_available"])
    |> Map.values()
    |> Enum.any?(&(&1 >= 500))
  end

  # As of 3.0
  defp vehicles_available(%{"num_vehicles_available" => num_vehicles_available}), do: num_vehicles_available
  # Before 3.0
  defp vehicles_available(%{"num_bikes_available" => num_bikes_available}), do: num_bikes_available

  def system_details(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :system_information)

    with {:feed_exists, true} <- {:feed_exists, not is_nil(feed_url)},
         {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      transform_localized_strings(json["data"])
    else
      {:feed_exists, false} ->
        nil

      e ->
        Logger.error("Cannot get GBFS system_information details: #{inspect(e)}")
        nil
    end
  end

  @doc """
  iex> %{"name" => "velhop", "timezone" => "Europe/Paris"} |> transform_localized_strings()
  %{"name" => "velhop", "timezone" => "Europe/Paris"}
  iex> %{name: "velhop", timezone: "Europe/Paris"} |> transform_localized_strings()
  %{name: "velhop", timezone: "Europe/Paris"}
  iex> %{name: [%{"text" => "velhop", "language" => "fr"}], timezone: "Europe/Paris"} |> transform_localized_strings()
  %{name: "velhop", timezone: "Europe/Paris"}
  """
  def transform_localized_strings(json) do
    Map.new(json, fn {k, v} ->
      if localized_string?(v) do
        {k, v |> hd() |> Map.get("text")}
      else
        {k, v}
      end
    end)
  end

  defp localized_string?(value) when is_list(value) do
    # See "Localized string" type on https://gbfs.org/specification/reference/#field-types
    match?(%{"text" => _, "language" => _}, value |> hd())
  end

  defp localized_string?(_), do: false

  def vehicle_types(%{"data" => _data} = payload) do
    feed_url = feed_url_by_name(payload, :vehicle_types)

    if is_nil(feed_url) do
      # https://gbfs.org/specification/reference/#vehicle_typesjson
      # > If this file is not included, then all vehicles in the feed are assumed to be non-motorized bicycles.
      ["bicycle"]
    else
      with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
           {:ok, json} <- Jason.decode(body) do
        json["data"]["vehicle_types"] |> Enum.map(& &1["form_factor"]) |> Enum.uniq()
      else
        _ -> nil
      end
    end
  end

  def languages(%{"data" => data} = payload) do
    if before_v3?(payload) do
      Map.keys(data)
    else
      feed_url = feed_url_by_name(payload, :system_information)

      with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(feed_url),
           {:ok, json} <- Jason.decode(body) do
        get_in(json, ["data", "languages"])
      else
        _ -> []
      end
    end
  end

  @spec versions(map()) :: [binary()] | nil
  def versions(%{"data" => _data} = payload) do
    versions_url = feed_url_by_name(payload, :gbfs_versions)

    if is_nil(versions_url) do
      [Map.get(payload, "version", "1.0")]
    else
      with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- cached_http_get(versions_url),
           {:ok, json} <- Jason.decode(body) do
        json["data"]["versions"] |> Enum.map(& &1["version"]) |> Enum.sort(:desc)
      else
        _ -> nil
      end
    end
  end

  @doc """
  Finds the main list of sub-feeds from a `gbfs.json`.

  Before v3 the order is: English first, then French otherwise the first language.
  As-of v3 there is only a single list of feeds.
  """
  def main_feeds(%{"data" => data} = payload) do
    if before_v3?(payload) do
      first_language = payload |> languages() |> Enum.at(0)
      (data["en"] || data["fr"] || data[first_language])["feeds"]
    else
      data["feeds"]
    end
  end

  @spec feed_url_by_name(map(), feed_name()) :: binary() | nil
  def feed_url_by_name(%{"data" => _} = payload, name) do
    (payload |> main_feeds() |> Enum.find(&feed_is_named?(&1, name)))["url"]
  end

  @spec feed_is_named?(map(), feed_name()) :: boolean()
  def feed_is_named?(%{"name" => feed_name}, name) do
    # Many people make the mistake of appending `.json` to feed names
    # so try to match this as well
    searches = [to_string(name), "#{name}.json"]

    if name == :vehicle_status do
      searches ++ ["free_bike_status", "free_bike_status.json"]
    else
      searches
    end
    |> Enum.member?(feed_name)
  end

  @spec has_feed?(map(), feed_name()) :: boolean()
  def has_feed?(%{"data" => _data} = payload, :vehicle_status) do
    not MapSet.disjoint?(MapSet.new(feeds(payload)), MapSet.new(["vehicle_status", "free_bike_status"]))
  end

  def has_feed?(%{"data" => _data} = payload, name) do
    Enum.member?(feeds(payload), to_string(name))
  end

  @spec feeds(map()) :: [binary()]
  def feeds(%{"data" => _data} = payload) do
    # Remove potential ".json" at the end of feed names as people
    # often make this mistake
    payload |> main_feeds() |> Enum.map(fn feed -> String.replace(feed["name"], ".json", "") end)
  end

  @doc """
  iex> non_nil_sum([1, 3])
  4
  iex> non_nil_sum([1, nil])
  1
  iex> non_nil_sum([nil])
  0
  """
  def non_nil_sum(values) do
    values |> Enum.reject(&is_nil/1) |> Enum.sum()
  end

  defp before_v3?(%{"version" => version}), do: String.starts_with?(version, ["1.", "2."])
  # No `version` key: GBFS 1.0
  # https://github.com/MobilityData/gbfs/blob/v1.1/gbfs.md#output-format
  defp before_v3?(%{}), do: true

  defp cached_http_get(url) do
    Transport.Cache.fetch(
      "#{__MODULE__}::http_get::#{url}",
      fn -> http_client().get(url) end,
      :timer.seconds(30)
    )
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
