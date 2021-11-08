defmodule Transport.DataChecker do
  @moduledoc """
  Use to check data, and act about it, like send email
  """
  alias Datagouvfr.Client.{Datasets, Discussions}
  alias Mailjet.Client
  alias DB.{Dataset, Repo, Resource}
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary
  alias Shared.Validation.GBFSValidator.Wrapper, as: GBFSValidator
  import TransportWeb.Router.Helpers
  import Ecto.Query
  require Logger

  def inactive_data do
    # we first check if some inactive datasets have reapeared
    to_reactivate_datasets = get_to_reactivate_datasets()
    reactivated_ids = Enum.map(to_reactivate_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^reactivated_ids)
    |> Repo.update_all(set: [is_active: true])

    # then we disable the unreachable datasets
    inactive_datasets = get_inactive_datasets()
    inactive_ids = Enum.map(inactive_datasets, & &1.datagouv_id)

    Dataset
    |> where([d], d.datagouv_id in ^inactive_ids)
    |> Repo.update_all(set: [is_active: false])

    send_inactive_dataset_mail(to_reactivate_datasets, inactive_datasets)
  end

  def get_inactive_datasets do
    Dataset
    |> where([d], d.is_active == true)
    |> Repo.all()
    |> Enum.reject(&Datasets.is_active?/1)
  end

  def get_to_reactivate_datasets do
    Dataset
    |> where([d], d.is_active == false)
    |> Repo.all()
    |> Enum.filter(&Datasets.is_active?/1)
  end

  def outdated_data(blank \\ false) do
    for delay <- [0, 7, 14],
        date = Date.add(Date.utc_today(), delay) do
      {delay, Dataset.get_expire_at(date)}
    end
    |> Enum.reject(fn {_, d} -> d == [] end)
    |> send_outdated_data_mail(blank)

    # |> post_outdated_data_comments(blank)
  end

  def post_outdated_data_comments(delays_datasets, blank) do
    case Enum.find(delays_datasets, fn {delay, _} -> delay == 7 end) do
      nil ->
        Logger.info("No datasets need a comment about outdated resources")

      {delay, datasets} ->
        Enum.map(datasets, fn r -> post_outdated_data_comment(r, delay, blank) end)
    end
  end

  def post_outdated_data_comment(dataset, delay, blank) do
    Discussions.post(
      dataset.datagouv_id,
      "Jeu de données arrivant à expiration",
      """
      Bonjour,
      Ce jeu de données arrive à expiration dans #{delay} jour#{if delay != 1 do
        "s"
      end}.
      Afin qu’il puisse continuer à être utilisé par les différents acteurs, il faut qu’il soit mis à jour prochainement.
      L’équipe transport.data.gouv.fr
      """,
      blank
    )
  end

  def gbfs_feeds do
    resources =
      Resource
      |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id)
      |> where([_r, d], d.type == "bike-scooter-sharing" and d.is_active)
      |> where([r, _d], like(r.url, "%gbfs.json") or r.format == "gbfs")
      |> where([r, _d], not fragment("? ~ ?", r.url, "station|free_bike"))
      |> Repo.all()

    Logger.info("Fetching details about #{Enum.count(resources)} GBFS feeds")

    resources
    |> Stream.map(fn r ->
      r |> compute_gbfs_feed_meta()
      # |> IO.inspect()
    end)
    |> Stream.run()
  end

  @spec compute_gbfs_feed_meta(Resource.t()) :: map()
  def compute_gbfs_feed_meta(resource) do
    Logger.debug(fn -> "Handling feed #{resource.url}" end)

    with {:ok, %{status_code: 200, body: body}} <- http_client().get(resource.url),
         {:ok, json} <- Jason.decode(body) do
      %{
        validation: gbfs_validation(resource),
        versions: gbfs_versions(json),
        languages: gbfs_languages(json),
        system_details: gbfs_system_details(json),
        types: gbfs_types(json),
        ttl: gbfs_ttl(json)
      }
    else
      e ->
        Logger.error(inspect(e))
        %{}
    end
  end

  @spec gbfs_validation(Resource.t()) :: GBFSValidationSummary.t() | nil
  defp gbfs_validation(resource) do
    case GBFSValidator.validate(resource.url) do
      {:ok, %GBFSValidationSummary{} = summary} -> summary
      {:error, _} -> nil
    end
  end

  defp gbfs_types(%{"data" => _data} = payload) do
    feed = payload |> gbfs_first_feed()

    has_bike_status = gbfs_has_feed?(feed, "free_bike_status")
    has_station_information = gbfs_has_feed?(feed, "station_information")

    cond do
      has_bike_status and has_station_information ->
        ["free_floating", "stations"]

      has_bike_status ->
        ["free_floating"]

      has_station_information ->
        ["stations"]

      true ->
        Logger.error("Cannot detect GBFS types for feed #{inspect(feed)}")
        nil
    end
  end

  defp gbfs_ttl(%{"data" => _data} = payload) do
    feed = payload |> gbfs_first_feed()

    value =
      case gbfs_types(payload) do
        ["free_floating", "stations"] -> feed |> gbfs_feed_url_by_name("free_bike_status")
        ["free_floating"] -> feed |> gbfs_feed_url_by_name("free_bike_status")
        ["stations"] -> feed |> gbfs_feed_url_by_name("station_information")
        nil -> payload["ttl"]
      end

    gbfs_feed_ttl(value)
  end

  defp gbfs_feed_ttl(value) when is_integer(value) and value >= 0, do: value

  defp gbfs_feed_ttl(feed_url) when is_binary(feed_url) do
    with {:ok, %{status_code: 200, body: body}} <- http_client().get(feed_url),
         {:ok, json} <- Jason.decode(body) do
      json["ttl"]
    else
      e ->
        Logger.error("Cannot get GBFS ttl details: #{inspect(e)}")
        nil
    end
  end

  defp gbfs_system_details(%{"data" => _data} = payload) do
    feed_url = payload |> gbfs_first_feed() |> gbfs_feed_url_by_name("system_information")

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

  defp gbfs_first_feed(%{"data" => data} = payload) do
    (data["en"] || data["fr"] || data[payload |> gbfs_languages() |> Enum.at(0)])["feeds"]
  end

  defp gbfs_languages(%{"data" => data}) do
    Map.keys(data)
  end

  @spec gbfs_versions(map()) :: [binary()] | nil
  defp gbfs_versions(%{"data" => _data} = payload) do
    gbfs_versions_url = payload |> gbfs_first_feed() |> gbfs_feed_url_by_name("gbfs_versions")

    if is_nil(gbfs_versions_url) do
      [Map.get(payload, "version", "1.0")]
    else
      with {:ok, %{status_code: 200, body: body}} <- http_client().get(gbfs_versions_url),
           {:ok, json} <- Jason.decode(body) do
        json["data"]["versions"] |> Enum.map(fn json -> json["version"] end) |> Enum.sort(:desc)
      else
        _ -> nil
      end
    end
  end

  @spec gbfs_feed_url_by_name(list(), binary()) :: binary() | nil
  defp gbfs_feed_url_by_name(feeds, name) do
    Enum.find(feeds, fn map -> gbfs_feed_is_named?(map, name) end)["url"]
  end

  @spec gbfs_feed_is_named?(map(), binary()) :: boolean()
  def gbfs_feed_is_named?(map, name) do
    # Many people make the mistake of append `.json` to feed names
    # so try to match this as well
    Enum.member?([name, "#{name}.json"], map["name"])
  end

  @spec gbfs_has_feed?([map()], binary()) :: boolean()
  def gbfs_has_feed?(feeds, name) do
    Enum.any?(feeds |> Enum.map(fn feed -> gbfs_feed_is_named?(feed, name) end))
  end

  defp make_str({delay, datasets}) do
    r_str =
      datasets
      |> Enum.map(&link_and_name/1)
      |> Enum.join("\n")

    """
    Jeux de données expirant #{delay_str(delay)}:

    #{r_str}
    """
  end

  defp delay_str(0), do: "demain"
  defp delay_str(d), do: "dans #{d} jours"

  defp link_and_name(dataset) do
    link = dataset_url(TransportWeb.Endpoint, :details, dataset.slug)
    name = dataset.title

    " * #{name} - #{link}"
  end

  defp make_outdated_data_body(datasets) do
    """
    Bonjour,
    Voici un résumé des jeux de données arrivant à expiration

    #{datasets |> Enum.map(&make_str/1) |> Enum.join("\n---------------------\n")}

    À vous de jouer !
    """
  end

  defp send_outdated_data_mail([], _), do: []

  defp send_outdated_data_mail(datasets, is_blank) do
    Client.send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données arrivant à expiration",
      make_outdated_data_body(datasets),
      "",
      is_blank
    )

    datasets
  end

  defp fmt_inactive_dataset([]), do: ""

  defp fmt_inactive_dataset(inactive_datasets) do
    datasets_str =
      inactive_datasets
      |> Enum.map(&link_and_name/1)
      |> Enum.join("\n")

    """
    Certains jeux de données ont disparus de data.gouv.fr :
    #{datasets_str}
    """
  end

  defp fmt_reactivated_dataset([]), do: ""

  defp fmt_reactivated_dataset(reactivated_datasets) do
    datasets_str =
      reactivated_datasets
      |> Enum.map(&link_and_name/1)
      |> Enum.join("\n")

    """
    Certains jeux de données disparus sont réapparus sur data.gouv.fr :
    #{datasets_str}
    """
  end

  defp make_inactive_dataset_body(reactivated_datasets, inactive_datasets) do
    reactivated_datasets_str = fmt_reactivated_dataset(reactivated_datasets)
    inactive_datasets_str = fmt_inactive_dataset(inactive_datasets)

    """
    Bonjour,
    #{inactive_datasets_str}
    #{reactivated_datasets_str}

    Il faut peut être creuser pour savoir si c'est normal.
    """
  end

  defp send_inactive_dataset_mail([], []), do: nil

  defp send_inactive_dataset_mail(reactivated_datasets, inactive_datasets) do
    Client.send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :contact_email),
      "Jeux de données qui disparaissent",
      make_inactive_dataset_body(reactivated_datasets, inactive_datasets),
      "",
      false
    )
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
