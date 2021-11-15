defmodule Transport.GBFSMetadata do
  @moduledoc """
  Compute and store metadata for GBFS resources.
  """
  alias DB.{Dataset, Repo, Resource}
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary
  alias Shared.Validation.GBFSValidator.Wrapper, as: GBFSValidator
  import Ecto.Query
  require Logger

  @doc """
  It is a bit of work, currently, to extract the list of `gbfs.json` endpoints,
  for instance because `format` is not enough alone to filter them.

  See https://github.com/etalab/transport-site/issues/1891#issuecomment-958888421 for some background.
  """
  def gbfs_feeds_query do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id)
    |> where([_r, d], d.type == "bike-scooter-sharing" and d.is_active)
    |> where([r, _d], like(r.url, "%gbfs.json") or r.format == "gbfs")
    |> where([r, _d], not fragment("? ~ ?", r.url, "station|free_bike"))
  end

  def set_gbfs_feeds_metadata do
    resources = gbfs_feeds_query() |> Repo.all()

    Logger.info("Fetching details about #{Enum.count(resources)} GBFS feeds")

    resources
    |> Stream.map(fn resource ->
      Logger.info("Fetching GBFS metadata for #{resource.url} (##{resource.id})")
      changeset = Resource.changeset(resource, %{format: "gbfs", metadata: compute_feed_metadata(resource)})
      Repo.update!(changeset)
    end)
    |> Stream.run()
  end

  @spec compute_feed_metadata(Resource.t()) :: map()
  def compute_feed_metadata(resource) do
    with {:ok, %{status_code: 200, body: body} = response} <-
           http_client().get(resource.url, [{"origin", website_url()}]),
         {:ok, json} <- Jason.decode(body) do
      %{
        validation: validation(resource),
        has_cors: has_cors?(response),
        is_cors_allowed: cors_headers_allows_self?(response),
        feeds: feeds(json),
        versions: versions(json),
        languages: languages(json),
        system_details: system_details(json),
        types: types(json),
        ttl: ttl(json)
      }
    else
      e ->
        Logger.error(inspect(e))
        %{}
    end
  end

  @spec validation(Resource.t()) :: GBFSValidationSummary.t() | nil
  defp validation(resource) do
    case GBFSValidator.validate(resource.url) do
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

  @doc """
  Find the value of the `Access-Control-Allow-Origin` header

  iex> Transport.GBFSMetadata.has_cors?(%HTTPoison.Response{headers: []})
  false

  iex> Transport.GBFSMetadata.has_cors?(%HTTPoison.Response{headers: [{"access-control-allow-origin", "*"}]})
  true

  iex> Transport.GBFSMetadata.has_cors?(%HTTPoison.Response{headers: [{"Access-Control-Allow-Origin", "*"}]})
  true
  """
  def has_cors?(%HTTPoison.Response{} = response) do
    not is_nil(cors_header_value(response))
  end

  @doc """
  Determines if the CORS header allows transport.data.gouv.fr

  iex> Transport.GBFSMetadata.cors_headers_allows_self?(%HTTPoison.Response{headers: []})
  false

  iex> Transport.GBFSMetadata.cors_headers_allows_self?(%HTTPoison.Response{headers: [{"access-control-allow-origin", "*"}]})
  true

  iex> Transport.GBFSMetadata.cors_headers_allows_self?(%HTTPoison.Response{headers: [{"Access-Control-Allow-Origin", "*"}]})
  true

  iex> Transport.GBFSMetadata.cors_headers_allows_self?(%HTTPoison.Response{headers: [{"Access-Control-Allow-Origin", "http://127.0.0.1:5100"}]})
  true
  """
  def cors_headers_allows_self?(%HTTPoison.Response{} = response) do
    Enum.member?([website_url(), "*"], cors_header_value(response))
  end

  defp ttl(%{"data" => _data} = payload) do
    feed = payload |> first_feed()

    value =
      case types(payload) do
        ["free_floating", "stations"] -> feed |> feed_url_by_name("free_bike_status")
        ["free_floating"] -> feed |> feed_url_by_name("free_bike_status")
        ["stations"] -> feed |> feed_url_by_name("station_information")
        nil -> payload["ttl"]
      end

    feed_ttl(value)
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

  defp first_feed(%{"data" => data} = payload) do
    (data["en"] || data["fr"] || data[payload |> languages() |> Enum.at(0)])["feeds"]
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
  defp feed_url_by_name(feeds, name) do
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
  defp website_url, do: TransportWeb.Endpoint.url()
end
