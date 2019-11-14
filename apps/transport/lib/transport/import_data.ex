defmodule Transport.ImportData do
  @moduledoc """
  Service use to import data from datagouv to psql
  """

  alias Datagouvfr.Client.CommunityResources
  alias Helpers
  alias Opendatasoft.UrlExtractor
  alias DB.{Dataset, Repo, Resource}
  require Logger
  import Ecto.Query

  def all, do: Dataset |> Repo.all() |> Enum.map(&call/1)

  def import_validate_all do
    all()
    Resource.validate_and_save_all()
  end

  def call(%Dataset{id: id, datagouv_id: datagouv_id, type: type}) do
    with {:ok, new_data} <- import_from_udata(datagouv_id, type),
         dataset <- Repo.get(Dataset, id),
         changeset <- Dataset.changeset(dataset, new_data) do
      Repo.update(changeset)
    else
      {:error, error} ->
        {:error, error}
    end
  end

  def import_from_udata(id, type) do
    base_url = Application.get_env(:transport, :datagouvfr_site)
    url      = "#{base_url}/api/1/datasets/#{id}/"

    Logger.info(" <message>  Importing dataset")
    Logger.info(" <id>       #{id}")
    Logger.info(" <url>      #{url}")

    with {:ok, response}  <- HTTPoison.get(url, [], hackney: [follow_redirect: true]),
         {:ok, json} <- Poison.decode(response.body),
         {:ok, dataset} <- get_dataset(json, type) do
      {:ok, dataset}
    else
      {:error, error} ->
        Logger.error("<message>  #{inspect error}")
        Logger.error("<id>       #{id}")
        Logger.error("<url>      #{url}")
        {:error, error}
    end
  end

  def get_dataset(%{"message" => error}, _), do: {:error, error}

  def get_dataset(%{} = dataset, type) do
    dataset =
      dataset
      |> Map.take(["title", "description", "license", "id", "slug", "frequency", "tags"])
      |> Map.put("datagouv_id", dataset["id"])
      |> Map.put("logo", get_logo_thumbnail(dataset))
      |> Map.put("full_logo", get_logo(dataset))
      |> Map.put("created_at", parse_date(dataset["created_at"]))
      |> Map.put("last_update", parse_date(dataset["last_update"]))
      |> Map.put("type", type)
      |> Map.put("organization", dataset["organization"]["name"])
      |> Map.put("resources", get_resources(dataset, type))
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
  def get_logo_thumbnail(%{"organization" => %{"logo_thumbnail" => logo}}), do: logo
  def get_logo_thumbnail(%{"owner" => %{"avatar_thumbnail" => logo}}), do: logo
  def get_logo_thumbnail(_), do: nil

  def get_dataset(_), do: {:error, "Dataset needs to be a map"}

  def get_resources(dataset, type) do
    dataset
    |> get_valid_resources(type)
    |> Enum.dedup_by(fn resource -> resource["url"] end)
    |> Enum.map(fn resource ->
            %{
            "url" => resource["url"],
            "format" => formated_format(resource, type),
            "title" => get_title(resource),
            "last_import" => DateTime.utc_now |> DateTime.to_string,
            "last_update" => resource["last_modified"],
            "latest_url" => resource["latest"],
            "id" => get_resource_id(resource),
            "is_available" => available?(resource)
          }
      end)
  end

  def available?(%{"extras" => %{"check:available" => available}}), do: available
  def available?(%{"url" => "https://static.data.gouv.fr/" <> _}), do: true
  def available?(%{"format" => "csv"}), do: true
  def available?(%{"type" => "api"}), do: true
  def available?(_), do: false

  def get_valid_resources(%{"resources" => resources}, type) do
    if Resource.is_transit_file?(type) do
      resources
      |> get_valid_gtfs_resources()
      |> Enum.concat(get_valid_netex_resources(resources))
      |> Enum.concat(get_valid_gtfs_rt_resources(resources))
    else
      resources
    end
  end

  def get_valid_gtfs_resources(resources) when is_list(resources) do
    cond do
      !Enum.empty?(l = Enum.filter(resources, &is_gtfs?/1)) -> l
      !Enum.empty?(l = Enum.filter(resources, &is_zip?/1)) -> l
      !Enum.empty?(l = UrlExtractor.get_csv_resources(resources)) -> l
      true -> []
    end
  end

  def get_valid_netex_resources(resources) when is_list(resources) do
    Enum.filter(resources, &is_netex?/1)
  end

  def get_valid_gtfs_rt_resources(resources) when is_list(resources) do
    Enum.filter(resources, &is_gtfs_rt?/1)
  end

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
  def is_gtfs?(%{} = params) do
    url = params["url"]
    cond do
      is_gtfs_rt?(params["format"]) -> false
      is_gtfs?(params["format"]) -> true
      is_format?(url, "json") -> false
      is_format?(url, "csv") -> false
      is_format?(url, "shp") -> false
      is_gtfs?(params["description"]) -> true
      is_gtfs?(params["title"]) -> true
      true -> false
    end
  end
  def is_gtfs?(str), do: is_format?(str, "gtfs")

  def is_gtfs_rt?(str), do: is_format?(str, "gtfs-rt") or is_format?(str, "gtfsrt")

  def is_format?(nil, _), do: false
  def is_format?(%{"format" => format}, expected), do: is_format?(format, expected)
  def is_format?(str, expected), do: str |> String.downcase |> String.contains?(expected)

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
  def is_zip?(%{"mime" => nil, "format" => format}), do: is_zip?(format)
  def is_zip?(%{"mime" => mime, "format" => nil}), do: is_zip?(mime)
  def is_zip?(%{"mime" => mime, "format" => format}), do: is_zip?(mime) || is_zip?(format)
  def is_zip?(str), do: is_format?(str, "zip")

  def is_netex?(r), do: is_format?(r, "netex")

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
  def check_download_url(%{"download_url" => nil}), do: false
  def check_download_url(%{"download_url" => _}), do: true

  @doc """
  Returns an date only part of the datetime

  ## Examples

      iex> ImportData.parse_date("2018-09-28T13:37:00")
      "2018-09-28"
  """
  def parse_date(date) when is_binary(date) do
    with {:ok, date} <- NaiveDateTime.from_iso8601(date) do
      date
      |> NaiveDateTime.to_date
      |> Date.to_string
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
  def formated_format(resource, type) do
    format = Map.get(resource, "format", "")

    cond do
      is_gtfs_rt?(format) -> "gtfs-rt"
      is_netex?(format) -> "netex"
      is_gtfs?(format) -> "GTFS"
      type == "public-transit" -> "GTFS"
      type == "train" -> "GTFS"
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
  def get_title(%{"title" => title}) when not is_nil(title), do: title
  def get_title(%{"url" => url}), do: Helpers.filename_from_url(url)

  defp get_resource_id(%{"url" => url}) do
    Resource |> where([r], r.url == ^url) |> select([r], r.id) |> Repo.one()
  end

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

  def is_realtime?(%{"format" => "gtfs-rt"}), do: true
  def is_realtime?(_), do: false

end
