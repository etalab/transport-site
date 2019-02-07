defmodule Transport.ImportData do
  @moduledoc """
  Service use to import data from datagouv to psql
  """

  alias Transport.{Dataset, Repo, Resource}
  require Logger

  @separators [?;, ?,]
  @csv_headers ["Download", "file", "Fichier"]

  def all, do: Dataset |> Repo.all() |> Enum.map(&call/1)

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
      |> Map.put("logo", dataset["organization"]["logo_thumbnail"])
      |> Map.put("full_logo", dataset["organization"]["logo"])
      |> Map.put("created_at", parse_date(dataset["created_at"]))
      |> Map.put("last_update", parse_date(dataset["last_update"]))
      |> Map.put("type", type)
      |> Map.put("resources", get_resources(dataset, type))

    case Map.get(dataset, "resources") do
      nil -> {:error, "No download uri found"}
      _ -> {:ok, dataset}
    end
  end

  def get_dataset(_), do: {:error, "Dataset needs to be a map"}

  def get_resources(dataset, type) do
    dataset
    |> get_valid_resources(type)
    |> Enum.dedup_by(fn resource -> resource["url"] end)
    |> Enum.map(fn resource ->
        case Repo.get_by(Resource, url: resource["url"]) do
          nil ->
            %{
            "url" => resource["url"],
            "format" => formated_format(resource),
            "title" => resource["title"],
            "last_import" => DateTime.utc_now |> DateTime.to_string,
          }
          r ->
            %{
            "format" => formated_format(resource),
            "title" => resource["title"],
            "last_import" => DateTime.utc_now |> DateTime.to_string,
            "id" => r.id
          }
        end
      end)
  end

  def get_valid_resources(%{"resources" => resources}, "public-transit") do
    cond do
      !Enum.empty?(l = Enum.filter(resources, &is_gtfs?/1)) -> l
      !Enum.empty?(l = Enum.filter(resources, &is_zip?/1)) -> l
      !Enum.empty?(l = get_csv_resources(resources)) -> l
      true -> []
    end
  end

  def get_valid_resources(%{"resources" => resources}, _) do
    resources
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

  """
  def is_gtfs?(%{} = params) do
    url = params["url"]
    is_gtfs?(params["format"]) or is_gtfs?(params["description"]) or
     (is_gtfs?(url) and !is_format?(url, "json") and !is_format?(url, "csv") and !is_format?(params, "shp"))
  end
  def is_gtfs?(str), do: is_format?(str, "gtfs")
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

  def get_csv_resources(resources) do
    csv_resources = filter_csv(resources)

    with {:ok, bodys} <- download_csv_list(csv_resources),
         {:ok, urls} <- get_url_from_csv(bodys) do
      Enum.map(urls, &(%{"url" => &1, "format" => "csv", "title" => &1}))
    else
      {:error, error} ->
        Logger.warn(" <message>  #{inspect error}")
        Enum.each(resources, fn resource ->
          Logger.warn(" <resource> #{resource["url"]}")
        end)

        []
    end
  end

  @doc """
  filter dataset with csv resources

  ## Examples
      iex> [%{"mime" => "text/csv", "format" => nil}]
      ...> |> ImportData.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => nil, "format" => "csv"}]
      ...> |> ImportData.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => nil, "format" => "CSV"}]
      ...> |> ImportData.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => "text/cv", "format" => nil}]
      ...> |> ImportData.filter_csv
      []

      iex> [%{"mime" => "text/csv", "format" => nil}, %{"mime" => "application/neptune", "format" => nil}]
      ...> |> ImportData.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

  """
  def filter_csv(resources) do
    for resource <- resources, "#{resource["mime"]}#{resource["format"]}" =~ ~r/csv/i do
      %{resource | "mime" => "text/csv", "format" => "csv"}
    end
  end

  @doc """
  filter csv http response

  ## Examples
      iex> {:ok, %{headers: [{"Content-Type", "text/csv"}]}}
      ...> |> ImportData.has_csv?
      true

      iex> {:ok, %{headers: [{"Content-Type", "application/zip"}]}}
      ...> |> ImportData.has_csv?
      false

      iex> {:error, "pouet"}
      ...> |> ImportData.has_csv?
      false

  """
  def has_csv?({:ok, %{headers: headers}}) do
     Enum.any?(headers, fn {k, v} ->
       k == "Content-Type" && String.contains?(v, "csv")
     end)
  end

  def has_csv?(_), do: false

  defp download_csv_list(resources) when is_list(resources) do
    resources
    |> Enum.map(&download_csv/1)
    |> Enum.filter(&has_csv?/1)
    |> case do
      bodys = [_ | _] -> {:ok, Enum.map(bodys, fn {_, v} -> v.body end)}
      [] -> {:error, "No csv found"}
    end
  end

  defp download_csv(%{"url" => url}) do
    case HTTPoison.get(url) do
      {:ok, response = %{status_code: 200}} ->
        {:ok, response}
      {:ok, response} ->
        {:error, "Bad status code, needs 200, wants #{response.status_code}"}
      {:error, error} ->
        {:error, error}
    end
  end

  @doc """
  Get a download from a CSVs if it exists

  ## Examples
      iex> ["name,file\\ntoulouse,http", "stop,lon,lat\\n1,48.8,2.3"]
      ...> |> ImportData.get_url_from_csv()
      "http"

      iex> |> ImportData.get_url_from_csv()
      {:error, "No column file"}

  """
  def get_url_from_csv(bodies) when is_list(bodies) do
    bodies
    |> Enum.map(&get_url_from_csv/1)
    |> Enum.filter(fn {status, _} -> status == :ok end)
    |> case do
      urls = [_ | _] -> {:ok, Enum.map(urls, fn {_, v} -> v end)}
      [] -> {:error, "No url found"}
    end
  end

  @doc """
  Get a download from a CSV if it exists

  ## Examples
      iex> "name,file\\ntoulouse,http"
      ...> |> ImportData.get_url_from_csv()
      {:ok, "http"}

      iex> "stop,lon,lat\\n1,48.8,2.3"
      ...> |> ImportData.get_url_from_csv()
      {:error, "No column file"}

      iex> "Donnees;format;Download\\r\\nHoraires des lignes TER;GTFS;https\\r\\n"
      ...> |> ImportData.get_url_from_csv()
      {:ok, "https"}

  """
  def get_url_from_csv(body) do
    @separators
    |> Enum.map(&(get_url_from_csv(&1, body)))
    |> Enum.filter(&(&1 != nil))
    |> case do
      [url | _] -> {:ok, url}
      _ -> {:error, "No column file"}
    end
  end

  def get_url_from_csv(separator, body) do
    case StringIO.open(body) do
      {:ok, out} ->
        out
        |> IO.binstream(:line)
        |> CSV.decode(headers: true, separator: separator)
        |> Enum.take(1)
        |> case do
          [ok: line] -> get_url_from_csv_line(line)
          [error: error] ->
            Logger.error(error)
            nil
          _ -> nil
        end
      {:error, error} ->
        Logger.error(error)
        nil
    end
  end

  def get_url_from_csv_line(line) do
    @csv_headers
    |> Enum.map(&(Map.get(line, &1)))
    |> Enum.filter(&(&1 != nil))
    |> case do
      [] -> nil
      [head | _] -> head
    end
  end

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
      ...> |> ImportData.formated_format
      "GTFS"

      iex> %{"last_modified" => "2017-11-29T23:54:05", "url" => "http1", "format" => "xls", "mime" => "foo"}
      ...> |> ImportData.formated_format
      "xls"
  """
  def formated_format(resource) do
    format = resource
    |> Map.get("format", "")

    if is_gtfs?(format), do: "GTFS", else: format
  end
end
