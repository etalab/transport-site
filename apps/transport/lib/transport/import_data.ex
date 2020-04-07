defmodule Transport.ImportData do
  @moduledoc """
  Service use to import data from datagouv to psql
  """

  alias Datagouvfr.Client.CommunityResources
  alias Helpers
  alias Opendatasoft.UrlExtractor
  alias DB.{Dataset, EPCI, Repo, Resource}
  require Logger
  import Ecto.Query

  @spec import_all_datasets :: :ok
  defp import_all_datasets do
    Logger.info("reimporting all datasets")

    datasets = Repo.all(Dataset)
    Task.Supervisor.async_stream_nolink(ImportTaskSupervisor, datasets, &import_dataset/1,
      max_concurrency: 5,
      timeout: 180_000
    )
    |> Enum.to_list()

    Logger.info("all datasets have been reimported")
  end

  @spec validate_all_resources() :: :ok
  def validate_all_resources() do
    Logger.info("Validating all resources")

    resources =
      Resource
      |> preload([:dataset, :validation])
      |> where([r], r.format == "GTFS")
      |> Repo.all()
      |> Enum.filter(&Resource.needs_validation/1)

    Logger.info("launching #{Enum.count(resources)} validations")

    validation_results = Task.Supervisor.async_stream_nolink(
      ImportTaskSupervisor,
      resources,
      &Resource.validate_and_save/1,
      max_concurrency: 5,
      timeout: 180_000
    )
    |> Enum.to_list()

    nb_failed = validation_results
    |> Enum.count(fn r -> case r do
        {:error, _} -> true
        _ -> false
      end
    end
    )

    Logger.info("All resources validated (#{nb_failed} failed / #{validation_results |> Enum.count()}}")
  end

  @spec import_validate_all :: :ok
  def import_validate_all do
    import_all_datasets()
    validate_all_resources()
  end

  @spec import_dataset(DB.Dataset.t()) :: {:ok, Ecto.Schema.t()} | {:error, any}
  def import_dataset(%Dataset{datagouv_id: datagouv_id, type: type}) do
    with {:ok, new_data} <- import_from_udata(datagouv_id, type),
         {:ok, changeset} <- Dataset.changeset(new_data) do
      Repo.update(changeset)
    else
      {:error, error} ->
        Logger.error("Unable to import data of dataset #{datagouv_id}: #{inspect(error)}")
        {:error, error}
    end
  end

  @spec import_from_udata(binary, binary) :: {:error, any} | {:ok, map}
  def import_from_udata(id, type) do
    base_url = Application.get_env(:transport, :datagouvfr_site)
    url = "#{base_url}/api/1/datasets/#{id}/"

    Logger.info("Importing dataset #{id} (url = #{url})")

    with {:ok, response} <- HTTPoison.get(url, [], hackney: [follow_redirect: true]),
         {:ok, json} <- Poison.decode(response.body),
         {:ok, dataset} <- get_dataset(json, type) do
      {:ok, dataset}
    else
      {:error, error} ->
        Logger.error("Error while importing dataset #{id} (url = #{url}) : #{inspect(error)}")
        {:error, error}
    end
  end

  @spec get_dataset(map, binary) :: {:error, any} | {:ok, map}
  def get_dataset(%{"message" => error}, _), do: {:error, error}

  def get_dataset(%{} = dataset, type) do
    dataset =
      dataset
      |> Map.take(["title", "description", "id", "slug", "frequency", "tags"])
      |> Map.put("datagouv_id", dataset["id"])
      |> Map.put("logo", get_logo_thumbnail(dataset))
      |> Map.put("full_logo", get_logo(dataset))
      |> Map.put("created_at", parse_date(dataset["created_at"]))
      |> Map.put("last_update", parse_date(dataset["last_update"]))
      |> Map.put("type", type)
      |> Map.put("organization", dataset["organization"]["name"])
      |> Map.put("resources", get_resources(dataset, type))
      |> Map.put("nb_reuses", get_nb_reuses(dataset))
      |> Map.put("licence", dataset["license"])
      |> Map.put("zones", get_associated_zones_insee(dataset))

    dataset =
      case has_realtime?(dataset, type) do
        {:ok, result} -> Map.put(dataset, "has_realtime", result)
        _ -> dataset
      end

    case Map.get(dataset, "resources") do
      nil -> {:error, "No download uri found"}
      _ -> {:ok, dataset}
    end
  end

  @doc """
  Get logo from datagouv dataset

  ## Examples

      iex> ImportData.get_logo(%{"organization" => %{"logo" => "logo"}})
      "logo"

      iex> ImportData.get_logo(%{"organization" => nil, "owner" => %{"avatar" => "logo"}})
      "logo"

  """
  @spec get_logo(map()) :: binary()
  def get_logo(%{"organization" => %{"logo" => logo}}), do: logo
  def get_logo(%{"owner" => %{"avatar" => logo}}), do: logo
  def get_logo(_), do: nil

  @doc """
  Get thumbnail from datagouv dataset

  ## Examples

      iex> ImportData.get_logo_thumbnail(%{"organization" => %{"logo_thumbnail" => "logo"}})
      "logo"

      iex> ImportData.get_logo_thumbnail(%{"organization" => nil, "owner" => %{"avatar_thumbnail" => "logo"}})
      "logo"

  """
  @spec get_logo_thumbnail(map()) :: binary()
  def get_logo_thumbnail(%{"organization" => %{"logo_thumbnail" => logo}}), do: logo
  def get_logo_thumbnail(%{"owner" => %{"avatar_thumbnail" => logo}}), do: logo
  def get_logo_thumbnail(_), do: nil

  @spec get_nb_reuses(map()) :: number()
  def get_nb_reuses(%{"metrics" => %{"reuses" => reuses}}), do: reuses
  def get_nb_reuses(_), do: 0

  @spec get_associated_zones_insee(map()) :: [binary()]
  defp get_associated_zones_insee(%{"spatial" => %{"zones" => zones}}) do
    zones
    |> Enum.flat_map(&fetch_data_gouv_zone_insee/1)
  end

  defp get_associated_zones_insee(_), do: []

  @spec fetch_data_gouv_zone_insee(binary()) :: [binary()]
  defp fetch_data_gouv_zone_insee(zone) do
    base_url = Application.get_env(:transport, :datagouvfr_site)
    url = "#{base_url}/api/1/spatial/zones/#{zone}"
    Logger.info("getting zone (url = #{url})")

    with {:ok, response} <- HTTPoison.get(url, [], hackney: [follow_redirect: true]),
         {:ok, json} <- Poison.decode(response.body),
         insee <- read_datagouv_zone(json) do
      insee
    else
      {:error, error} ->
        Logger.error("Error while reading zone #{zone} (url = #{url}) : #{inspect(error)}")
        []
    end
  end

  @spec read_datagouv_zone(map()) :: [binary()]
  defp read_datagouv_zone(%{
         "features" => [
           %{
             "properties" => %{
               "level" => "fr:commune",
               "keys" => %{
                 "insee" => insee
               }
             }
           }
           | _
         ]
       }) do
    [insee]
  end

  defp read_datagouv_zone(%{
         "features" => [
           %{
             "properties" => %{
               "level" => "fr:epci",
               "code" => code
             }
           }
           | _
         ]
       }) do
    # For the EPCI we get the list of cities contained by the EPCI
    EPCI
    |> Repo.get_by(code: code)
    |> case do
      nil ->
        Logger.warn("impossible to find epci #{code}, no cities associated to the dataset")
        []

      epci ->
        epci.communes_insee
    end
  end

  defp read_datagouv_zone(%{"id" => id}) do
    Logger.info("For the moment we can only handle cities, we cannot handle the zone #{id}")
    []
  end

  defp read_datagouv_zone(z) do
    Logger.info("invalid format we cannot handle the zone #{inspect(z)}")
    []
  end

  @spec get_resources(map(), binary()) :: [map()]
  def get_resources(dataset, type) do
    dataset
    |> get_valid_resources(type)
    |> Enum.dedup_by(fn resource -> resource["url"] end)
    |> Enum.map(fn resource ->
      %{
        "url" => resource["url"],
        "format" => formated_format(resource, type),
        "title" => get_title(resource),
        "last_import" => DateTime.utc_now() |> DateTime.to_string(),
        "last_update" => resource["last_modified"],
        # For ODS gtfs as csv we do not have a 'latest' field
        # (the 'latest' field is the stable data.gouv.fr url)
        "latest_url" => resource["latest"] || resource["url"],
        "id" => get_resource_id(resource, dataset["id"]),
        "is_available" => available?(resource)
      }
    end)
  end

  @spec available?(map()) :: boolean
  def available?(%{"extras" => %{"check:available" => available}}), do: available
  def available?(%{"url" => "https://static.data.gouv.fr/" <> _}), do: true
  def available?(%{"url" => "https://demo.data.gouv.fr/" <> _}), do: true
  def available?(%{"format" => "csv"}), do: true
  def available?(%{"type" => "api"}), do: true

  def available?(%{"url" => url}) do
    case HTTPoison.head(url) do
      {:ok, %HTTPoison.Response{status_code: 200}} -> true
      _ -> false
    end
  end

  @spec get_valid_resources(map(), binary()) :: [map()]
  def get_valid_resources(%{"resources" => resources}, type) do
    if type == "public-transit" do
      resources
      |> get_valid_gtfs_resources()
      |> Enum.concat(get_valid_netex_resources(resources))
      |> Enum.concat(get_valid_gtfs_rt_resources(resources))
    else
      resources
    end
  end

  @spec get_valid_gtfs_resources([map()]) :: [map()]
  def get_valid_gtfs_resources(resources) do
    cond do
      !Enum.empty?(l = Enum.filter(resources, &is_gtfs?/1)) -> l
      !Enum.empty?(l = Enum.filter(resources, &is_zip?/1)) -> l
      !Enum.empty?(l = UrlExtractor.get_csv_resources(resources)) -> l
      true -> []
    end
  end

  @spec get_valid_netex_resources([map()]) :: [map()]
  def get_valid_netex_resources(resources), do: Enum.filter(resources, &is_netex?/1)

  @spec get_valid_gtfs_rt_resources([map()]) :: [map()]
  def get_valid_gtfs_rt_resources(resources), do: Enum.filter(resources, &is_gtfs_rt?/1)

  @doc """
  Is it a gtfs file?

  ## Examples

      iex> ImportData.is_gtfs?("netex")
      false

      iex> ImportData.is_gtfs?("sncf.tgv.GtFs.zip.tar.gz.7z")
      true

      iex> ImportData.is_gtfs?(%{"format" => "neptune"})
      false

      iex> ImportData.is_gtfs?(%{"format" => "gtfs-rt"})
      false

  """
  @spec is_gtfs?(map()) :: boolean()
  def is_gtfs?(%{} = params) do
    cond do
      is_gtfs_rt?(params["format"]) -> false
      is_gtfs?(params["format"]) -> true
      is_format?(params["url"], ["json", "csv", "shp", "pdf"]) -> false
      is_gtfs?(params["description"]) -> true
      is_gtfs?(params["title"]) -> true
      true -> false
    end
  end

  def is_gtfs?(str), do: is_format?(str, "gtfs")

  @spec is_gtfs_rt?(binary() | map()) :: boolean()
  def is_gtfs_rt?(str), do: is_format?(str, "gtfs-rt") or is_format?(str, "gtfsrt")

  @doc """
  check the format
      iex> ImportData.is_format?("netex", ["GTFS", "netex"])
      true

      iex> ImportData.is_format?("pouet", ["GTFS", "netex"])
      false

      iex> ImportData.is_format?(%{"format" => "netex"}, "netex")
      true
  """
  @spec is_format?(binary() | map(), binary() | [binary()]) :: boolean
  def is_format?(nil, _), do: false
  def is_format?(%{"format" => format}, expected), do: is_format?(format, expected)
  def is_format?(value, [head | tail]), do: is_format?(value, head) || is_format?(value, tail)
  def is_format?(str, expected), do: str |> String.downcase() |> String.contains?(expected)

  @doc """
  Is the ressource a zip file?

  ## Examples
      iex> ImportData.is_zip?(%{"mime" => "application/zip", "format" => nil})
      true

      iex> ImportData.is_zip?(%{"mime" => nil, "format" => "zip"})
      true

      iex> ImportData.is_zip?(%{"mime" => nil, "format" => "ZIP"})
      true

      iex> ImportData.is_zip?(%{"mime" => "application/exe", "format" => nil})
      false
  """
  @spec is_zip?(binary() | map()) :: boolean()
  def is_zip?(%{"mime" => nil, "format" => format}), do: is_zip?(format)
  def is_zip?(%{"mime" => mime, "format" => nil}), do: is_zip?(mime)
  def is_zip?(%{"mime" => mime, "format" => format}), do: is_zip?(mime) || is_zip?(format)
  def is_zip?(str), do: is_format?(str, "zip")

  @spec is_netex?(binary() | map()) :: boolean()
  def is_netex?(%{} = params) do
    cond do
      is_format?(params["format"], "netex") -> true
      is_format?(params["description"], "netex") -> true
      true -> false
    end
  end

  def is_netex?(s), do: is_format?(s, "netex")

  @doc """
  Check for licence, returns ["bad_license"] if the licence is not "odc-odbl"
  or "fr-lo".

  ## Examples

      iex> ImportData.check_license(%{"license" => "bliblablou"})
      false

      iex> ImportData.check_license(%{"license" => "odc-odbl"})
      true

      iex> ImportData.check_license(%{"license" => "fr-lo"})
      true

  """
  @spec check_license(map()) :: boolean()
  def check_license(%{"license" => "odc-odbl"}), do: true
  def check_license(%{"license" => "fr-lo"}), do: true
  def check_license(_), do: false

  @doc """
  Check for download uri, returns ["no_download_url"] if there's no download_url

  ## Examples

      iex> ImportData.check_download_url(%{"download_url" => nil})
      false

      iex> ImportData.check_download_url(%{"download_url" => "http"})
      true

  """
  @spec check_download_url(map()) :: boolean()
  def check_download_url(%{"download_url" => nil}), do: false
  def check_download_url(%{"download_url" => _}), do: true

  @doc """
  Returns an date only part of the datetime

  ## Examples

      iex> ImportData.parse_date("2018-09-28T13:37:00")
      "2018-09-28"
  """
  @spec parse_date(binary()) :: binary()
  def parse_date(date) when is_binary(date) do
    with {:ok, date} <- NaiveDateTime.from_iso8601(date) do
      date
      |> NaiveDateTime.to_date()
      |> Date.to_string()
    end
  end

  def parse_date(nil), do: nil

  @doc """
  Formats the file format in a human readable form

  ## Examples

      iex> %{"last_modified" => "2017-11-29T23:54:05", "url" => "http1", "format" => "gtfs.zip", "mime" => "foo"}
      ...> |> ImportData.formated_format("")
      "GTFS"

      iex> %{"last_modified" => "2017-11-29T23:54:05", "url" => "http1", "format" => "xls", "mime" => "foo"}
      ...> |> ImportData.formated_format("")
      "xls"

      iex> %{"format" => "csv"}
      ...> |> ImportData.formated_format("public-transit")
      "GTFS"
  """
  @spec formated_format(map(), binary()) :: binary()
  def formated_format(resource, type) do
    format = Map.get(resource, "format", "")

    cond do
      is_gtfs_rt?(format) -> "gtfs-rt"
      is_netex?(format) -> "netex"
      is_gtfs?(format) -> "GTFS"
      type == "public-transit" -> "GTFS"
      true -> format
    end
  end

  @doc """
  Gets the title of a resource or returns its filename if it doesn’t exist

  ## Examples

      iex> ImportData.get_title(%{"title" => "Timetables", "url" => "https://example.com/bus.gtfs.zip"})
      "Timetables"

      iex> ImportData.get_title(%{"title" => nil, "url" => "https://example.com/bus.gtfs.zip"})
      "bus.gtfs.zip"

      iex> ImportData.get_title(%{"url" => "https://example.com/bus.gtfs.zip"})
      "bus.gtfs.zip"
  """
  @spec get_title(map()) :: binary()
  def get_title(%{"title" => title}) when not is_nil(title), do: title
  def get_title(%{"url" => url}), do: Helpers.filename_from_url(url)

  @spec get_resource_id(map(), binary()) :: Resource.t()
  defp get_resource_id(%{"url" => url}, dataset_id) do
    Resource
    |> join(:left, [r], d in Dataset, on: r.dataset_id == d.id)
    |> where([r, _d], r.url == ^url)
    |> where([_r, d], d.datagouv_id == ^dataset_id)
    |> select([r], r.id)
    |> Repo.one()
  end

  @spec has_realtime?(map, binary) :: {:error, false} | {:ok, boolean}
  def has_realtime?(dataset, "public-transit") do
    if Enum.any?(dataset["resources"], &is_realtime?/1) do
      {:ok, true}
    else
      case CommunityResources.get(dataset["id"]) do
        {:ok, resources} -> {:ok, Enum.any?(resources, &is_realtime?/1)}
        {:error, _error} -> {:error, false}
      end
    end
  end

  def has_realtime?(_, _), do: {:ok, false}

  @spec is_realtime?(map()) :: boolean
  def is_realtime?(%{"format" => "gtfs-rt"}), do: true
  def is_realtime?(_), do: false
end
