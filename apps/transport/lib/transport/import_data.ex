defmodule Transport.ImportData do
  @moduledoc """
  Service use to import data from datagouv to psql
  """

  alias Datagouvfr.Client.CommunityResources
  alias Helpers
  alias Opendatasoft.UrlExtractor
  alias DB.{Dataset, EPCI, LogsImport, Repo, Resource}
  require Logger
  import Ecto.Query

  @max_import_concurrent_jobs Application.get_env(:transport, :max_import_concurrent_jobs)

  @spec import_all_datasets :: :ok
  def import_all_datasets do
    Logger.info("reimporting all datasets")

    datasets = Repo.all(Dataset)

    results =
      ImportTaskSupervisor
      |> Task.Supervisor.async_stream_nolink(datasets, &import_dataset/1,
        max_concurrency: @max_import_concurrent_jobs,
        timeout: 180_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    nb_failed =
      results
      |> Enum.count(&invalid_result?/1)

    Logger.info("all datasets have been reimported (#{nb_failed} failures / #{Enum.count(results)})")
  end

  @spec validate_all_resources() :: :ok
  def validate_all_resources(force \\ false) do
    Logger.info("Validating all resources")

    resources_id =
      Resource
      |> select([r], r.id)
      |> Repo.all()

    Logger.info("launching #{Enum.count(resources_id)} validations")

    validation_results =
      ImportTaskSupervisor
      |> Task.Supervisor.async_stream_nolink(
        resources_id,
        fn r_id -> Resource.validate_and_save(r_id, force) end,
        max_concurrency: @max_import_concurrent_jobs,
        timeout: 180_000
      )
      |> Enum.to_list()

    nb_failed =
      validation_results
      |> Enum.count(&invalid_result?/1)

    Logger.info("All resources validated (#{nb_failed} failures / #{validation_results |> Enum.count()}}")
  end

  @spec import_validate_all :: :ok
  def import_validate_all do
    import_all_datasets()
    validate_all_resources()
  end

  def refresh_places do
    Logger.info("Refreshing places...")
    # NOTE: I could not find a way to call "refresh_places()" directly
    {:ok, _result} = Repo.query("REFRESH MATERIALIZED VIEW places;")
  end

  def generate_import_logs!(
        %Dataset{id: dataset_id, datagouv_id: datagouv_id},
        options
      ) do
    success = options |> Keyword.fetch!(:success)
    msg = options |> Keyword.get(:msg, "")

    now = DateTime.truncate(DateTime.utc_now(), :second)

    insert_result =
      Repo.insert(%LogsImport{
        datagouv_id: datagouv_id,
        timestamp: now,
        is_success: success,
        dataset_id: dataset_id,
        error_msg: msg
      })

    # if the insertion fails, we retry with a basic error message
    with {:error, _} <- insert_result do
      Repo.insert(%LogsImport{
        datagouv_id: datagouv_id,
        timestamp: now,
        is_success: success,
        dataset_id: dataset_id,
        error_msg: "error message could not be logged"
      })
    end
  end

  @spec import_dataset_logged(DB.Dataset.t()) :: {:ok, Ecto.Schema.t()} | {:error, any}
  def import_dataset_logged(dataset) do
    result = import_dataset!(dataset)
    generate_import_logs!(dataset, success: true)
    {:ok, result}
  rescue
    e ->
      generate_import_logs!(dataset, success: false, msg: inspect(e))

      Logger.error("Import of dataset has failed (id:  #{dataset.id}, datagouv_id: #{dataset.datagouv_id})")
      Logger.error(Exception.format(:error, e, __STACKTRACE__))

      {:error, inspect(e)}
  end

  @spec import_dataset!(DB.Dataset.t()) :: Ecto.Schema.t()
  def import_dataset!(%Dataset{
        datagouv_id: datagouv_id,
        type: type
      }) do
    dataset_map_from_data_gouv = import_from_data_gouv!(datagouv_id, type)
    {:ok, changeset} = Dataset.changeset(dataset_map_from_data_gouv)
    result = Repo.update!(changeset)

    refresh_places()
    result
  end

  @spec import_from_data_gouv!(binary, binary) :: map
  def import_from_data_gouv!(datagouv_id, type) do
    base_url = Application.get_env(:transport, :datagouvfr_site)
    url = "#{base_url}/api/1/datasets/#{datagouv_id}/"

    Logger.info("Importing dataset #{datagouv_id} from data.gouv.fr (url = #{url})")

    # We'll have to verify the behaviour of hackney/httpoison for follow_redirect: how
    # many redirects are allowed? Is an error raised after a while or not? etc.
    response = HTTPoison.get!(url, [], hackney: [follow_redirect: true])
    json = Jason.decode!(response.body)
    {:ok, dataset} = prepare_dataset_from_data_gouv_response(json, type)

    dataset
  end

  @spec prepare_dataset_from_data_gouv_response(map, binary) :: {:error, any} | {:ok, map}
  def prepare_dataset_from_data_gouv_response(%{"message" => error}, _), do: {:error, error}

  def prepare_dataset_from_data_gouv_response(%{} = data_gouv_resp, type) do
    dataset =
      data_gouv_resp
      |> Map.take(["title", "description", "id", "slug", "frequency", "tags"])
      |> Map.put("datagouv_id", data_gouv_resp["id"])
      |> Map.put("logo", get_logo_thumbnail(data_gouv_resp))
      |> Map.put("full_logo", get_logo(data_gouv_resp))
      |> Map.put("created_at", parse_date(data_gouv_resp["created_at"]))
      |> Map.put("last_update", parse_date(data_gouv_resp["last_update"]))
      |> Map.put("type", type)
      |> Map.put("organization", data_gouv_resp["organization"]["name"])
      |> Map.put("resources", get_resources(data_gouv_resp, type))
      |> Map.put("nb_reuses", get_nb_reuses(data_gouv_resp))
      |> Map.put("licence", data_gouv_resp["license"])
      |> Map.put("zones", get_associated_zones_insee(data_gouv_resp))

    case Map.get(data_gouv_resp, "resources") do
      nil -> {:error, "dataset #{data_gouv_resp["id"]} has no resource"}
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
         {:ok, json} <- Jason.decode(response.body),
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

  defp read_datagouv_zone(%{"features" => [%{"id" => id} | _]}) do
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
    |> Enum.concat(get_community_resources(dataset))
    |> Enum.uniq_by(fn resource -> resource["url"] end)
    |> Enum.map(fn resource ->
      is_community_resource = resource["is_community_resource"] == true

      %{
        "url" => resource["url"],
        "format" => formated_format(resource, type, is_community_resource),
        "title" => get_title(resource),
        "last_import" => DateTime.utc_now() |> DateTime.to_string(),
        "last_update" => resource["last_modified"],
        # For ODS gtfs as csv we do not have a 'latest' field
        # (the 'latest' field is the stable data.gouv.fr url)
        "latest_url" => resource["latest"] || resource["url"],
        "id" => get_resource_id(resource, dataset["id"]),
        "datagouv_id" => resource["id"],
        "is_available" => available?(resource),
        "is_community_resource" => is_community_resource,
        "community_resource_publisher" => get_publisher(resource),
        "description" => resource["description"],
        "filesize" => resource["filesize"],
        "content_hash" => Hasher.get_content_hash(resource["url"]),
        "original_resource_url" => get_original_resource_url(resource)
      }
    end)
  end

  @spec available?(map()) :: boolean
  # Temporarily disabled since data.gouv.fr has been blocked by ODS
  # def available?(%{"extras" => %{"check:available" => available}}), do: available
  def available?(%{"url" => "https://static.data.gouv.fr/" <> _}), do: true
  def available?(%{"url" => "https://demo.data.gouv.fr/" <> _}), do: true
  def available?(%{"format" => "csv"}), do: true
  def available?(%{"type" => "api"}), do: true

  def available?(%{"url" => url}) do
    # NOTE: ssl options are a hotfix for https://github.com/etalab/transport-site/issues/1564
    # We will be able to remove them once OTP is updated to 23 (https://github.com/etalab/transport-site/issues/1584)
    case HTTPoison.head(url, [], ssl: [versions: [:"tlsv1.2"]]) do
      {:ok, %HTTPoison.Response{status_code: code}} when code >= 200 and code < 400 -> true
      _ -> false
    end
  end

  @spec get_valid_resources(map(), binary()) :: [map()]
  def get_valid_resources(%{"resources" => resources}, "public-transit") do
    resources
    |> get_valid_gtfs_resources()
    |> Enum.concat(get_valid_netex_resources(resources))
    |> Enum.concat(get_valid_gtfs_rt_resources(resources))
  end

  def get_valid_resources(%{"resources" => resources}, _type) do
    resources
  end

  @spec get_valid_gtfs_resources([map()]) :: [map()]
  def get_valid_gtfs_resources(resources) do
    cond do
      !Enum.empty?(l = Enum.filter(resources, &is_gtfs?/1)) -> l
      !Enum.empty?(l = Enum.filter(resources, &is_zip?/1)) -> l
      !Enum.empty?(l = UrlExtractor.get_gtfs_csv_resources(resources)) -> l
      true -> []
    end
  end

  @spec get_valid_netex_resources([map()]) :: [map()]
  def get_valid_netex_resources(resources), do: Enum.filter(resources, &is_netex?/1)

  @spec get_valid_gtfs_rt_resources([map()]) :: [map()]
  def get_valid_gtfs_rt_resources(resources), do: Enum.filter(resources, &is_gtfs_rt?/1)

  @spec get_community_resources(map()) :: [map()]
  def get_community_resources(%{"id" => id}) do
    case CommunityResources.get(id) do
      {:ok, resources} ->
        resources
        |> Enum.map(fn r -> Map.put(r, "is_community_resource", true) end)

      {:error, error} ->
        Logger.warn("impossible to get community ressource for dataset #{id} => #{inspect(error)}")

        []
    end
  end

  @doc """
  Is it a gtfs file?

  ## Examples

      iex> ImportData.is_gtfs?("NeTEx")
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
      is_format?(params["url"], ["json", "csv", "shp", "pdf", "7z"]) -> false
      is_format?(params["format"], ["NeTEx", "neptune"]) -> false
      is_format?(params["title"], "NeTEx") -> false
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
      iex> ImportData.is_format?("NeTEx", ["GTFS", "NeTEx"])
      true

      iex> ImportData.is_format?("pouet", ["GTFS", "NeTEx"])
      false

      iex> ImportData.is_format?(%{"format" => "NeTEx"}, "NeTEx")
      true
  """
  @spec is_format?(binary() | map(), binary() | [binary()]) :: boolean
  def is_format?(nil, _), do: false
  def is_format?(%{"format" => format}, expected), do: is_format?(format, expected)
  def is_format?(value, [head | tail]), do: is_format?(value, head) || is_format?(value, tail)
  def is_format?(_, []), do: false

  def is_format?(str, expected),
    do: str |> String.downcase() |> String.contains?(String.downcase(expected))

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
      is_format?(params["format"], "NeTEx") -> true
      is_format?(params["description"], "NeTEx") -> true
      true -> false
    end
  end

  def is_netex?(s), do: is_format?(s, "NeTEx")

  @spec is_neptune?(binary() | map()) :: boolean()
  def is_neptune?(s), do: is_format?(s, "neptune")

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
      ...> |> ImportData.formated_format("", false)
      "GTFS"

      iex> %{"last_modified" => "2017-11-29T23:54:05", "url" => "http1", "format" => "xls", "mime" => "foo"}
      ...> |> ImportData.formated_format("", false)
      "xls"

      iex> %{"format" => "csv"}
      ...> |> ImportData.formated_format("public-transit", false)
      "GTFS"
  """
  @spec formated_format(map(), binary(), bool()) :: binary()
  def formated_format(resource, type, is_community_resource) do
    format = Map.get(resource, "format", "")

    cond do
      is_gtfs_rt?(format) -> "gtfs-rt"
      is_netex?(format) -> "NeTEx"
      is_neptune?(format) -> "Neptune"
      is_gtfs?(format) -> "GTFS"
      type == "public-transit" and not is_community_resource -> "GTFS"
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

  @spec get_original_resource_url(map()) :: binary() | nil
  def get_original_resource_url(%{"extras" => %{"transport:original_resource_url" => url}}),
    do: url

  def get_original_resource_url(_), do: nil

  @spec invalid_result?({:exit, any} | {:ok, any}) :: boolean
  defp invalid_result?({:ok, {:error, _}}), do: true
  defp invalid_result?({:ok, _}), do: false
  defp invalid_result?({:exit, _}), do: true

  defp get_publisher(%{"organization" => %{"name" => name}}), do: name

  defp get_publisher(%{"owner" => %{"first_name" => first_name, "last_name" => last_name}}),
    do: first_name <> " " <> last_name

  defp get_publisher(_), do: nil
end
