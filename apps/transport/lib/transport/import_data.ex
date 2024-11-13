defmodule Transport.ImportData do
  @moduledoc """
  Service use to import data from datagouv to psql
  """

  alias Datagouvfr.Client.CommunityResources
  alias Helpers
  alias Opendatasoft.UrlExtractor
  alias DB.{Commune, Dataset, LogsImport, Repo, Resource}
  alias Transport.Shared.ResourceSchema
  require Logger
  import Ecto.Query

  defp availability_checker, do: Transport.AvailabilityChecker.Wrapper.impl()

  def max_import_concurrent_jobs do
    Application.fetch_env!(:transport, :max_import_concurrent_jobs)
  end

  @spec import_all_datasets :: :ok
  def import_all_datasets do
    Logger.info("reimporting all active datasets")

    datasets = DB.Dataset.base_with_hidden_datasets() |> Repo.all()

    results =
      ImportTaskSupervisor
      |> Task.Supervisor.async_stream_nolink(datasets, &import_dataset_logged/1,
        max_concurrency: max_import_concurrent_jobs(),
        timeout: 180_000,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    nb_failed =
      results
      |> Enum.count(&invalid_result?/1)

    Logger.info("all datasets have been reimported (#{nb_failed} failures / #{Enum.count(results)})")
  end

  @spec import_validate_all :: :ok
  def import_validate_all do
    import_all_datasets()
    # validation is now gone, replaced by DB.MultiValidation
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
    msg = options |> Keyword.get(:msg)

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
        error_msg: "Error message could not be logged"
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
    {:ok, dataset_map_from_data_gouv} = import_from_data_gouv(datagouv_id, type)
    {:ok, changeset} = Dataset.changeset(dataset_map_from_data_gouv)
    result = Repo.update!(changeset)

    refresh_places()
    result
  end

  @spec import_from_data_gouv(binary, binary) :: {:ok, map}
  def import_from_data_gouv(datagouv_id, type) do
    base_url = Application.fetch_env!(:transport, :datagouvfr_site)
    url = "#{base_url}/api/1/datasets/#{datagouv_id}/"

    Logger.info("Importing dataset #{datagouv_id} from data.gouv.fr (url = #{url})")

    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    # We use a direct call with the HTTP client instead of using the datagouv API client module
    # because of redirects.
    # We'll have to verify the behaviour of hackney/httpoison for follow_redirect: how
    # many redirects are allowed? Is an error raised after a while or not? etc.
    response = http_client.get!(url, [], hackney: [follow_redirect: true])
    json = Jason.decode!(response.body)
    {:ok, dataset} = prepare_dataset_from_data_gouv_response(json, type)

    {:ok, dataset}
  end

  @spec prepare_dataset_from_data_gouv_response(map, binary) :: {:error, any} | {:ok, map}
  def prepare_dataset_from_data_gouv_response(%{"message" => error}, _), do: {:error, error}

  def prepare_dataset_from_data_gouv_response(%{} = data_gouv_resp, type) do
    dataset =
      data_gouv_resp
      |> Map.take(["description", "id", "slug", "frequency", "tags"])
      |> Map.put("datagouv_title", data_gouv_resp["title"])
      |> Map.put("datagouv_id", data_gouv_resp["id"])
      |> Map.put("logo", get_logo_thumbnail(data_gouv_resp))
      |> Map.put("full_logo", get_logo(data_gouv_resp))
      |> Map.put("created_at", parse_datetime(data_gouv_resp["created_at"]))
      |> Map.put("last_update", parse_datetime(data_gouv_resp["last_update"]))
      |> Map.put("type", type)
      |> Map.put("organization", data_gouv_resp["organization"])
      |> Map.put("resources", get_resources(data_gouv_resp, type))
      |> Map.put("nb_reuses", get_nb_reuses(data_gouv_resp))
      |> Map.put("licence", licence(data_gouv_resp))
      |> Map.put("archived_at", parse_datetime(data_gouv_resp["archived"]))
      |> Map.put("zones", get_associated_zones_insee(data_gouv_resp))
      |> Map.put("is_active", true)

    case Map.get(data_gouv_resp, "resources") do
      nil -> {:error, "dataset #{data_gouv_resp["id"]} has no resource"}
      _ -> {:ok, dataset}
    end
  end

  @doc """
  Set the licence according to the datagouv response.

  ## Examples

  iex> licence(%{"license" => "odc-odbl"})
  "odc-odbl"
  iex> licence("odc-odbl")
  nil
  """
  def licence(%{"license" => datagouv_licence}), do: datagouv_licence
  def licence(_), do: nil

  @doc """
  Get logo from datagouv dataset

  ## Examples

      iex> get_logo(%{"organization" => %{"logo" => "logo"}})
      "logo"

      iex> get_logo(%{"organization" => nil, "owner" => %{"avatar" => "logo"}})
      "logo"

  """
  @spec get_logo(map()) :: binary()
  def get_logo(%{"organization" => %{"logo" => logo}}), do: logo
  def get_logo(%{"owner" => %{"avatar" => logo}}), do: logo
  def get_logo(_), do: nil

  @doc """
  Get thumbnail from datagouv dataset

  ## Examples

      iex> get_logo_thumbnail(%{"organization" => %{"logo_thumbnail" => "logo"}})
      "logo"

      iex> get_logo_thumbnail(%{"organization" => nil, "owner" => %{"avatar_thumbnail" => "logo"}})
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
    base_url = Application.fetch_env!(:transport, :datagouvfr_site)
    url = "#{base_url}/api/1/spatial/zones/#{zone}/"
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
  def read_datagouv_zone(%{
        "features" => [
          %{
            "properties" => %{
              "level" => "fr:commune",
              "code" => insee
            }
          }
          | _
        ]
      }) do
    [insee]
  end

  def read_datagouv_zone(%{
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
    Commune
    |> where([c], c.epci_insee == ^code)
    |> select([c], c.insee)
    |> Repo.all()
  end

  def read_datagouv_zone(%{"features" => [%{"id" => id} | _]}) do
    Logger.info("For the moment we can only handle cities, we cannot handle the zone #{id}")
    []
  end

  def read_datagouv_zone(z) do
    Logger.info("invalid format we cannot handle the zone #{inspect(z)}")
    []
  end

  @spec get_resources(map(), binary()) :: [map()]
  def get_resources(dataset, type) do
    dataset
    |> get_valid_resources(type)
    |> Enum.concat(get_community_resources(dataset))
    |> Enum.uniq_by(fn resource -> resource["url"] end)
    |> Enum.map_reduce(0, fn resource, display_position ->
      is_community_resource = resource["is_community_resource"] == true
      existing_resource = get_existing_resource(resource, dataset["id"]) || %{}

      resource =
        resource
        |> Map.put("url", cleaned_url(resource["url"]))

      format = formated_format(resource, type, is_community_resource)

      {%{
         "url" => resource["url"],
         "format" => format,
         "title" => get_title(resource),
         "last_import" => DateTime.utc_now(),
         "last_update" => parse_datetime(resource["last_modified"]),
         # For ODS gtfs as csv we do not have a 'latest' field
         # (the 'latest' field is the stable data.gouv.fr url)
         "latest_url" => resource["latest"] || resource["url"],
         # GOTCHA: `filetype` is set to `file` for exports coming from ODS
         # https://github.com/opendatateam/udata-ods/issues/250
         "filetype" => resource["filetype"],
         "type" => resource["type"],
         "id" => existing_resource[:id],
         "datagouv_id" => resource["id"],
         "is_available" => availability_checker().available?(format, resource["url"]),
         "is_community_resource" => is_community_resource,
         "community_resource_publisher" => get_publisher(resource),
         "description" => resource["description"],
         "filesize" => resource["filesize"],
         "original_resource_url" => get_original_resource_url(resource),
         "schema_name" => ResourceSchema.guess_name(resource, type),
         "schema_version" => ResourceSchema.guess_version(resource),
         "metadata" => resource["metadata"],
         "display_position" => display_position
       }, display_position + 1}
    end)
    |> elem(0)
  end

  @doc """
  Clean or replace some resource' URLs.

  iex> cleaned_url("http://exs.sismo2.cityway.fr/GTFS.aspx?key=SISMO&amp;OperatorCode=CG60L3")
  "https://exs.sismo2.cityway.fr/GTFS.aspx?key=SISMO&OperatorCode=CG60L3"
  iex> cleaned_url("http://example.com/file.zip")
  "http://example.com/file.zip"
  iex> cleaned_url("http://exs.sismo2.cityway.fr")
  "https://exs.sismo2.cityway.fr"
  """
  def cleaned_url(url) do
    uri = URI.parse(url)

    if is_binary(uri.host) and String.match?(uri.host, ~r/^exs\.(\w)+\.cityway\.fr$/) do
      cleaned_query =
        if is_nil(uri.query) do
          nil
        else
          uri.query |> String.replace("&amp;", "&")
        end

      %{uri | scheme: "https", query: cleaned_query, port: 443} |> URI.to_string()
    else
      url
    end
  end

  @spec get_valid_resources(map(), binary()) :: [map()]
  def get_valid_resources(%{"resources" => resources}, "public-transit") do
    resources
    |> get_valid_gtfs_resources()
    |> Enum.concat(get_valid_netex_resources(resources))
    |> Enum.concat(get_valid_gtfs_rt_resources(resources))
    |> Enum.concat(get_valid_siri_resources(resources))
    |> Enum.concat(get_valid_siri_lite_resources(resources))
    |> Enum.concat(get_valid_documentation_resources(resources))
  end

  def get_valid_resources(%{"resources" => resources}, _type) do
    resources
  end

  @spec get_valid_documentation_resources([map()]) :: [map()]
  def get_valid_documentation_resources(resources) do
    resources
    |> Enum.filter(&documentation?/1)
    |> Enum.map(fn resource -> %{resource | "type" => "documentation"} end)
  end

  @spec get_valid_gtfs_resources([map()]) :: [map()]
  def get_valid_gtfs_resources(resources) do
    cond do
      !Enum.empty?(l = Enum.filter(resources, &gtfs?/1)) -> l
      !Enum.empty?(l = Enum.filter(resources, &zip?/1)) -> l
      !Enum.empty?(l = UrlExtractor.get_gtfs_csv_resources(resources)) -> l
      true -> []
    end
  end

  @spec get_valid_netex_resources([map()]) :: [map()]
  def get_valid_netex_resources(resources) do
    resources =
      cond do
        !Enum.empty?(l = Enum.filter(resources, &netex?/1)) -> l
        !Enum.empty?(l = UrlExtractor.get_netex_csv_resources(resources)) -> l
        true -> []
      end

    resources |> Enum.map(fn r -> %{r | "format" => "NeTEx"} end)
  end

  @spec get_valid_gtfs_rt_resources([map()]) :: [map()]
  def get_valid_gtfs_rt_resources(resources) do
    resources =
      cond do
        !Enum.empty?(l = Enum.filter(resources, &gtfs_rt?/1)) -> l
        !Enum.empty?(l = UrlExtractor.get_gtfs_rt_csv_resources(resources)) -> l
        true -> []
      end

    resources |> Enum.map(fn r -> %{r | "format" => "gtfs-rt"} end)
  end

  @doc """
  iex> get_valid_siri_resources([%{"format" => "siri", "id" => 1}, %{"format" => "xxx", "id" => 2}])
  [%{"format" => "SIRI", "id" => 1}]
  """
  @spec get_valid_siri_resources([map()]) :: [map()]
  def get_valid_siri_resources(resources) do
    resources |> Enum.filter(&siri?/1) |> Enum.map(fn r -> %{r | "format" => "SIRI"} end)
  end

  @spec get_valid_siri_lite_resources([map()]) :: [map()]
  def get_valid_siri_lite_resources(resources) do
    resources |> Enum.filter(&siri_lite?/1) |> Enum.map(fn r -> %{r | "format" => "SIRI Lite"} end)
  end

  @spec get_community_resources(map()) :: [map()]
  def get_community_resources(%{"id" => datagouv_id}) do
    case CommunityResources.get(datagouv_id) do
      {:ok, resources} ->
        resources
        |> Enum.map(fn r -> Map.put(r, "is_community_resource", true) end)

      {:error, error} ->
        Logger.warning("impossible to get community ressource for dataset #{datagouv_id} => #{inspect(error)}")

        []
    end
  end

  @doc """
  iex> ods_resource?(%{"format" => "json", "title" => "GTFS (json)", "harvest" => %{"uri" => "https://data.angers.fr/api/explore/v2.1/catalog/datasets/angers-loire-metropole-horaires-reseau-irigo-gtfs-rt/exports/json"}})
  true
  iex> ods_resource?(%{"format" => "GTFS", "title" => "GTFS été"})
  false
  iex> ods_resource?(%{"format" => "csv", "title" => "Export au format CSV"})
  true
  iex> ods_resource?(%{"format" => "csv", "title" => "Export au format CSV"})
  true
  """
  # Will soon be legacy, after DCAT migration
  # (see https://github.com/etalab/transport-site/issues/3647)
  def ods_resource?(%{"title" => title})
      when title in ["Export au format CSV", "Export au format JSON"],
      do: true

  def ods_resource?(%{"harvest" => %{"uri" => uri}}) do
    # Possible URL:
    # https://data.angers.fr/api/explore/v2.1/catalog/datasets/angers-loire-metropole-horaires-reseau-irigo-gtfs-rt/exports/json
    String.match?(uri, ~r{/api/explore/v\d+\.\d+/catalog/datasets/.*/exports/\w+(\?use_labels=(true|false))?$}i)
  end

  def ods_resource?(_), do: false

  @doc """
  Is it a GTFS file?

  ## Examples

  iex> gtfs?("NeTEx")
  false
  iex> gtfs?("sncf.tgv.GtFs.zip.tar.gz.7z")
  true
  iex> gtfs?(%{"format" => "gtfs-rt"})
  false
  iex> gtfs?(%{"format" => "pb", "url" => "https://example.com/GtfsRt/GtfsRT.TCRA.pb"})
  false
  iex> gtfs?(%{"format" => "gtfs", "description" => "Lien vers le fichier GTFS utilisé avec le GTFS-RT."})
  true
  iex> gtfs?(%{"format" => "zip", "title" => "GTFS RTM", "url" => "https://example.com/api/Export/v1/GetExportedDataFile?ExportFormat=Gtfs&OperatorCode=RTM"})
  true
  iex> gtfs?(%{"description" => "gtfs", "title" => "Export au format CSV"})
  false
  iex> gtfs?(%{"title" => "Angers GTFS (json)", "format" => "json", "harvest" => %{"uri" => "https://example.com/api/explore/v2.1/catalog/datasets/foo/exports/json"}})
  false
  iex> gtfs?(%{"format" => "gtfs", "title" => "Export au format CSV"})
  true
  iex> gtfs?(%{"url" => "https://example.com/documentation-gtfs.pdf", "type" => "documentation"})
  false
  """
  @spec gtfs?(map()) :: boolean()
  # credo:disable-for-next-line
  def gtfs?(%{} = params) do
    cond do
      gtfs?(params["format"]) -> true
      ods_resource?(params) or documentation?(params) -> false
      gtfs_rt?(params) -> false
      format?(params["url"], ["json", "csv", "shp", "pdf", "7z"]) -> false
      format?(params["format"], "NeTEx") -> false
      netex?(params["title"]) -> false
      gtfs?(params["title"]) -> true
      gtfs?(params["description"]) -> true
      true -> false
    end
  end

  def gtfs?(str), do: format?(str, "gtfs") and not gtfs_rt?(str)

  @doc """
  Is it a GTFS-RT feed?

  ## Examples

  iex> gtfs_rt?(%{"format" => "pb", "url" => "https://example.com/GtfsRt/GtfsRT.TCRA.pb"})
  true
  iex> gtfs_rt?(%{"format" => "pb", "url" => "https://example.com/feed.pb", "title" => "GTFS-RT réseau ORIZO"})
  true
  iex> gtfs_rt?(%{"format" => "gtfs-rt"})
  true
  iex> Enum.all?(["GTFS RT", "gtfs rt", "GTFS-RT"], &gtfs_rt?/1)
  true
  iex> Enum.all?(["GTFS RTM", "gtfs théorique", "ZIP GTFS"], &(! gtfs_rt?(&1)))
  true
  iex> gtfs_rt?(%{"description" => "gtfs-rt", "title" => "Export au format CSV"})
  false
  iex> gtfs_rt?(%{"format" => "json", "title" => "GTFS-RT vehicle positions", "description" => "gtfs-rt", "harvest" => %{"uri" => "https://example.com/api/explore/v2.1/catalog/datasets/foo/exports/json"}})
  false
  iex> gtfs_rt?(%{"format" => "gtfs-rt", "title" => "Export au format CSV"})
  true
  """
  @spec gtfs_rt?(binary() | map() | nil) :: boolean()
  def gtfs_rt?(%{} = params) do
    cond do
      gtfs_rt?(params["format"]) -> true
      ods_resource?(params) or documentation?(params) -> false
      gtfs_rt?(params["title"]) -> true
      gtfs_rt?(params["description"]) -> true
      gtfs_rt?(params["url"]) -> true
      true -> false
    end
  end

  def gtfs_rt?(str) when is_binary(str), do: String.match?(str, ~r/\b(gtfs-rt|gtfsrt|gtfs rt)\b/i)
  def gtfs_rt?(_), do: false

  @doc """
  iex> documentation?(%{"title" => "Fichier", "format" => "gtfs"})
  false
  iex> documentation?(%{"title" => "Fichier", "format" => "csv"})
  false
  iex> documentation?(%{"title" => "Description des données", "format" => "PDF"})
  true
  iex> documentation?(%{"type" => "documentation", "format" => "docx"})
  true
  iex> documentation?(nil)
  false
  iex> documentation?(%{"type" => "main", "title" => "Documentation SIRI", "format" => "xlsx"})
  true
  """
  @spec documentation?(any()) :: boolean()
  def documentation?(%{"type" => "documentation"}), do: true

  def documentation?(%{"title" => resource_title, "format" => _} = args) do
    String.match?(resource_title, ~r/\bdocumentation\b/i) or documentation_format?(args)
  end

  def documentation?(_), do: false

  @doc """
  Determines if a format is likely a documentation format.

  iex> documentation_format?("PDF")
  true
  iex> documentation_format?("GTFS")
  false
  """
  @spec documentation_format?(map() | binary() | nil) :: boolean()
  def documentation_format?(%{"format" => format}), do: documentation_format?(format)

  def documentation_format?(format) do
    format?(format, ["pdf", "svg", "html"])
  end

  @doc """
  iex> siri?("siri lite")
  false
  iex> siri?("SIRI")
  true
  iex> siri?(%{"format" => "SIRI"})
  true
  iex> siri?(%{"title" => "Export au format CSV", "format" => "SIRI"})
  false
  iex> siri?(%{"title" => "Flux SIRI", "format" => "csv", "harvest" => %{"uri" => "https://example.com/api/explore/v2.1/catalog/datasets/foo/exports/json"}})
  false
  iex> siri?(%{"title" => "https://api.okina.fr/gateway/cae/realtime", "format" => "bin", "description" => "API temps réel au format SIRI"})
  true
  iex> siri?(%{"type" => "documentation", "title" => "Documentation de l'API SIRI"})
  false
  """
  @spec siri?(binary() | map() | nil) :: boolean()
  def siri?(%{} = params) do
    cond do
      siri_lite?(params) -> false
      ods_resource?(params) or documentation?(params) -> false
      format?(params, "siri") -> true
      siri?(params["title"]) -> true
      siri?(params["description"]) -> true
      siri?(params["url"]) -> true
      true -> false
    end
  end

  def siri?(format), do: not siri_lite?(format) and format?(format, "siri")

  @doc """
  iex> siri_lite?("siri lite")
  true
  iex> siri_lite?("siri-lite")
  true
  iex> siri_lite?("SIRI Lite")
  true
  iex> siri_lite?(%{"format" => "SIRI-Lite"})
  true
  iex> siri_lite?(%{"title" => "SIRI-Lite stop monitoring", "url" => "https://example.com/utw/ws/siri/2.0/stop-monitoring.json?AccountKey=opendata-flux-gtfs-rt", "format" => "octet-stream", "description" => "Informations au format SIRI-Lite"})
  true
  iex> siri_lite?("SIRI")
  false
  """
  @spec siri_lite?(binary() | map() | nil) :: boolean()
  def siri_lite?(%{} = params) do
    cond do
      ods_resource?(params) or documentation?(params) -> false
      format?(params, "SIRI Lite") -> true
      siri_lite?(params["title"]) -> true
      siri_lite?(params["description"]) -> true
      siri_lite?(params["url"]) -> true
      true -> false
    end
  end

  def siri_lite?(format), do: format?(format, "SIRI Lite")

  @doc """
  Does a format matches another format/list of candidate formats?

  iex> format?("NeTEx", ["GTFS", "NeTEx"])
  true
  iex> format?("pouet", ["GTFS", "NeTEx"])
  false
  iex> format?(%{"format" => "NeTEx"}, "NeTEx")
  true
  iex> format?("siri lite", "SIRI-Lite")
  true
  """
  @spec format?(binary() | map() | nil, binary() | [binary()]) :: boolean
  def format?(nil, _), do: false
  def format?(%{"format" => declared_format}, expected), do: format?(declared_format, expected)
  def format?(value, [head | tail]), do: format?(value, head) || format?(value, tail)
  def format?(_, []), do: false

  def format?(str, expected),
    do: String.contains?(clean_format(str), clean_format(expected))

  @doc """
  iex> clean_format("GTFS-RT")
  "gtfsrt"
  iex> clean_format("GTFS RT")
  "gtfsrt"
  iex> clean_format("SIRI Lite")
  "sirilite"
  iex> clean_format("Ne[-tex")
  "ne[tex"
  """
  def clean_format(format),
    do: format |> String.downcase() |> String.replace(~r/[^0-9a-zA-Z\[\]]/, "")

  @doc """
  Is the ressource a zip file?

  ## Examples
      iex> zip?(%{"mime" => "application/zip", "format" => nil})
      true

      iex> zip?(%{"mime" => nil, "format" => "zip"})
      true

      iex> zip?(%{"mime" => nil, "format" => "ZIP"})
      true

      iex> zip?(%{"mime" => "application/exe", "format" => nil})
      false
  """
  @spec zip?(binary() | map() | nil) :: boolean()
  def zip?(%{"mime" => nil, "format" => format}), do: zip?(format)
  def zip?(%{"mime" => mime, "format" => nil}), do: zip?(mime)
  def zip?(%{"mime" => mime, "format" => format}), do: zip?(mime) || zip?(format)
  def zip?(str), do: format?(str, "zip")

  @doc """
  Is the resource a NeTEx file?

  ## Examples
  iex> netex?(%{"format" => "netex"})
  true
  iex> netex?(%{"description" => "Un super fichier NeTEx.", "format" => "zip"})
  true
  iex> netex?(%{"url" => "https://example.com/netex.zip", "format" => "zip"})
  true
  iex> netex?(%{"url" => "https://example.com/export.zip", "format" => "zip", "title" => "Export NeTEx été"})
  true
  iex> netex?(%{"url" => "https://example.com/gtfs.zip", "format" => "zip"})
  false
  iex> netex?(%{"url" => "https://example.com/doc-netex.pdf", "type" => "documentation"})
  false
  iex> netex?(%{"title" => "Export au format CSV", "format" => "netex"})
  true
  iex> netex?(%{"title" => "Angers NeTEx (json)", "format" => "json", "harvest" => %{"uri" => "https://example.com/api/explore/v2.1/catalog/datasets/foo/exports/json"}})
  false
  """
  @spec netex?(binary() | map() | nil) :: boolean()
  def netex?(%{} = params) do
    cond do
      netex?(params["format"]) -> true
      ods_resource?(params) or documentation?(params) -> false
      netex?(params["title"]) -> true
      netex?(params["description"]) -> true
      netex?(params["url"]) -> true
      true -> false
    end
  end

  def netex?(s), do: format?(s, "NeTEx")

  @doc """
  Check for download uri, returns ["no_download_url"] if there's no download_url

  ## Examples

      iex> check_download_url(%{"download_url" => nil})
      false

      iex> check_download_url(%{"download_url" => "http"})
      true

  """
  @spec check_download_url(map()) :: boolean()
  def check_download_url(%{"download_url" => nil}), do: false
  def check_download_url(%{"download_url" => _}), do: true

  @doc """
  Parses an ISO 8601 string into a datetime.

  iex> parse_datetime("2018-09-28T13:37:00+00:00")
  ~U[2018-09-28 13:37:00Z]
  iex> parse_datetime(nil)
  nil
  """
  @spec parse_datetime(binary() | nil) :: DateTime.t() | nil
  def parse_datetime(date) when is_binary(date) do
    {:ok, datetime, 0} = DateTime.from_iso8601(date)
    datetime
  end

  def parse_datetime(nil), do: nil

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

      iex> %{"url" => "https://example.com/gbfs.json"}
      ...> |> ImportData.formated_format("bike-scooter-sharing", false)
      "gbfs"

      iex> %{"url" => "https://example.com/gbfs/v2"}
      ...> |> ImportData.formated_format("car-motorbike-sharing", false)
      "gbfs"

      iex> %{"url" => "https://example.com/gbfs/free_bike_status.json", "format" => "json"}
      ...> |> ImportData.formated_format("bike-scooter-sharing", false)
      "json"

      iex> formated_format(%{"url" => "https://data.strasbourg.eu/api/datasets/1.0/zfe_voie_exception/alternative_exports/zfe_voie_speciale_eurometropole_strasbourg_geojson", "format" => "a"}, "low-emission-zones", false)
      "geojson"

      iex> formated_format(%{"format" => "GeoJSON"}, "low-emission-zones", false)
      "geojson"

      iex> formated_format(%{"format" => "siri-lite"}, "public-transit", false)
      "SIRI Lite"

      iex> formated_format(%{"format" => "pdf", "type" => "documentation"}, "public-transit", false)
      "pdf"

      iex> formated_format(%{"format" => "zip", "description" => "Lieux de mobilités au format netex"}, "locations", false)
      "NeTEx"

      iex> formated_format(%{"format" => "zip", "title" => "files-netex-half-summer-autumn-2023.zip"}, "public-transit", false)
      "NeTEx"

      iex> formated_format(%{"format" => "zip", "title" => "gtfs.zip", "description" => "GTFS qui va avec le GTFS-RT"}, "public-transit", false)
      "GTFS"

      iex> formated_format(%{"format" => "netex", "title" => "Export au format CSV"}, "public-transit", false)
      "NeTEx"
  """
  @spec formated_format(map(), binary(), bool()) :: binary()
  # credo:disable-for-next-line
  def formated_format(resource, type, is_community_resource) do
    format = Map.get(resource, "format", "")
    is_documentation = Map.get(resource, "type", "") == "documentation"

    cond do
      gtfs_rt?(format) -> "gtfs-rt"
      netex?(resource) -> "NeTEx"
      gtfs?(resource) -> "GTFS"
      siri_lite?(format) -> "SIRI Lite"
      siri?(format) -> "SIRI"
      geojson?(resource, format) -> "geojson"
      type == "public-transit" and not is_documentation and not is_community_resource -> "GTFS"
      type in ["bike-scooter-sharing", "car-motorbike-sharing"] and gbfs?(resource) -> "gbfs"
      true -> format
    end
  end

  defp geojson?(%{"url" => url}, format), do: format?(format, "geojson") or String.ends_with?(url, "geojson")
  defp geojson?(_, format), do: format?(format, "geojson")

  @doc """
  iex> url = "https://data.strasbourg.eu/api/explore/v2.1/catalog/datasets/velhop_gbfs/exports/csv?use_labels=false"
  iex> gbfs?(%{"url" => url , "format" => "csv", "harvest" => %{"uri" => url}})
  false
  iex> gbfs?(%{"url" => "https://example.com/gbfs/free_bike_status.json", "format" => "json"})
  false
  iex> gbfs?(%{"url" => "https://example.com/gbfs/gbfs.json", "format" => "json"})
  true
  """
  def gbfs?(%{"url" => url} = params) do
    cond do
      ods_resource?(params) ->
        false

      String.contains?(url, "gbfs") ->
        Enum.all?(["free_bike", "station"] |> Enum.map(fn w -> not String.contains?(url, w) end))

      true ->
        false
    end
  end

  @doc """
  Gets the title of a resource or returns its filename if it doesn’t exist

  ## Examples

      iex> get_title(%{"title" => "Timetables", "url" => "https://example.com/bus.gtfs.zip"})
      "Timetables"

      iex> get_title(%{"title" => nil, "url" => "https://example.com/bus.gtfs.zip"})
      "bus.gtfs.zip"

      iex> get_title(%{"url" => "https://example.com/bus.gtfs.zip"})
      "bus.gtfs.zip"
  """
  @spec get_title(map()) :: binary()
  def get_title(%{"title" => title}) when not is_nil(title), do: title
  def get_title(%{"url" => url}), do: Helpers.filename_from_url(url)

  @spec get_existing_resource(map(), binary()) :: Resource.t() | nil
  # ODS CSV resources are identified only with their URL, as their resource datagouv id is not unique.
  # For regular resources, we can identify them by resource datagouv id or by their url.
  defp get_existing_resource(%{"is_ods_csv" => true, "url" => url}, dataset_datagouv_id) do
    get_existing_resource_by_url(url, dataset_datagouv_id)
  end

  defp get_existing_resource(%{"url" => url, "id" => resource_datagouv_id}, dataset_datagouv_id) do
    get_existing_resource_by_datagouv_id(resource_datagouv_id, dataset_datagouv_id) ||
      get_existing_resource_by_url(url, dataset_datagouv_id)
  end

  defp get_existing_resource_by_url(url, dataset_datagouv_id) do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id)
    |> where([r, d], r.url == ^url and d.datagouv_id == ^dataset_datagouv_id)
    |> select([r], map(r, [:id]))
    |> Repo.one()
  end

  defp get_existing_resource_by_datagouv_id(resource_datagouv_id, dataset_datagouv_id) do
    Resource
    |> join(:inner, [r], d in Dataset, on: r.dataset_id == d.id)
    |> where([r, d], r.datagouv_id == ^resource_datagouv_id and d.datagouv_id == ^dataset_datagouv_id)
    |> select([r], map(r, [:id]))
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
