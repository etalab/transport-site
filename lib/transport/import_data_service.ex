defmodule Transport.ImportDataService do
  @moduledoc """
  Service use to import data from datagouv to mongodb
  """

  require Logger

  @separators [?;, ?,]
  @csv_headers ["Download", "file", "Fichier"]

  def call(%{"_id" => mongo_id, "id" => id}) do
    case import_from_udata(id) do
      {:ok, new_data} ->
        Mongo.find_one_and_update(:mongo,
                                  "datasets",
                                  %{"_id" => mongo_id},
                                  %{"$set" => new_data},
                                  pool: DBConnection.Poolboy)
      {:error, error} ->
        {:error, error}
    end
  end

  def import_from_udata(id) do
    base_url = Application.get_env(:transport, :datagouvfr_site)
    url      = "#{base_url}/api/1/datasets/#{id}/"

    Logger.info(" <message>  Importing dataset")
    Logger.info(" <id>       #{id}")

    with {:ok, response}  <- HTTPoison.get(url, [], hackney: [follow_redirect: true]),
         {:ok, json} <- Poison.decode(response.body),
         {:ok, dataset} <- get_dataset(json),
         anomalies <- get_anomalies(dataset) do
      {:ok, Map.put(dataset, "anomalies", anomalies)}
    else
      {:error, error} ->
        Logger.error("<message>  #{inspect error}")
        Logger.error("<id>       #{id}")
        {:error, error}
    end
  end

  def get_dataset(%{"message" => error}) do
    {:error, error}
  end

  def get_dataset(%{} = dataset) do
    dataset =
      dataset
      |> Map.take(["title", "description", "license", "id", "slug", "frequency", "tags"])
      |> Map.put("datagouv_id", dataset["id"])
      |> Map.put("logo", dataset["organization"]["logo_thumbnail"])
      |> Map.put("full_logo", dataset["organization"]["logo"])
      |> Map.put("task_id", Map.get(dataset, "task_id"))
      |> Map.put("download_url", get_download_url(dataset))
      |> Map.put("format", "GTFS")
      |> Map.put("created_at", parse_date(dataset["created_at"]))
      |> Map.put("last_update", parse_date(dataset["last_update"]))

    case Map.get(dataset, "download_url") do
      nil -> {:error, "No download uri found"}
      _ -> {:ok, dataset}
    end
  end

  def get_dataset(_), do: {:error, "Dataset needs to be a map"}

  def get_download_url(%{"resources" => resources}) do
    cond do
      (l = get_url(resources, &filter_gtfs/1)) != nil -> l
      (l = get_url(resources, &filter_zip/1)) != nil -> l
      (csv_list = filter_csv(resources)) != [] ->
        with {:ok, bodys} <- download_csv_list(csv_list),
             {:ok, urls} <- get_url_from_csv(bodys) do
          List.first(urls)
        else
          {:error, error} ->
            Logger.warn(" <message>  #{inspect error}")

            Enum.each(resources, fn resource ->
              Logger.warn(" <resource> #{resource["url"]}")
            end)

            nil
        end
      true ->
        nil
    end
  end

  @doc """
  Get latest resource url from a set of resources filtered by filter

  ## Examples
      iex> [%{"last_modified" => "2017-11-29T23:54:05", "url" => "http"}]
      ...> |> ImportDataService.get_url(&(&1))
      "http"

      iex> [%{"last_modified" => "2017-11-29T23:54:05", "url" => "http1"}, %{"last_modified" => "2017-12-29T23:54:05", "url" => "http2"}]
      ...> |> ImportDataService.get_url(&(&1))
      "http2"

      iex> [%{"last_modified" => "2017-11-29T23:54:05", "url" => "http1"}, %{"last_modified" => "2017-12-29T23:54:05"}]
      ...> |> ImportDataService.get_url(&(&1))
      "http1"

  """
  def get_url(resources, filter) do
    resources
    |> Enum.filter(&(Map.has_key?(&1, "url") && Map.has_key?(&1, "last_modified")))
    |> filter.()
    |> case do
      [] -> nil
      list  -> list
            |> Enum.sort_by(&(&1["last_modified"]))
            |> List.last
            |> Map.get("url")
    end
  end

  @doc """
  filter gtfs resources

  ## Examples
      iex> [%{"format" => "GTFS"}]
      ...> |> ImportDataService.filter_gtfs
      [%{"format" => "GTFS"}]

      iex> [%{"format" => "gtf"}]
      ...> |> ImportDataService.filter_gtfs
      []

      iex> [%{"format" => "GTFS"}, %{"format" => "zip"}]
      ...> |> ImportDataService.filter_gtfs
      [%{"format" => "GTFS"}]

  """
  def filter_gtfs(resources) do
    Enum.filter(resources, fn %{"format" => format} ->
      String.downcase(format) == "gtfs"
    end)
  end

  @doc """
  filter dataset with zip resources

  ## Examples
      iex> [%{"mime" => "application/zip", "format" => nil}]
      ...> |> ImportDataService.filter_zip
      [%{"mime" => "application/zip", "format" => "zip"}]

      iex> [%{"mime" => nil, "format" => "zip"}]
      ...> |> ImportDataService.filter_zip
      [%{"mime" => "application/zip", "format" => "zip"}]

      iex> [%{"mime" => nil, "format" => "ZIP"}]
      ...> |> ImportDataService.filter_zip
      [%{"mime" => "application/zip", "format" => "zip"}]

      iex> [%{"mime" => "application/exe", "format" => nil}]
      ...> |> ImportDataService.filter_zip
      []

      iex> [%{"mime" => "application/zip", "format" => nil}, %{"mime" => "application/neptune", "format" => nil}]
      ...> |> ImportDataService.filter_zip
      [%{"mime" => "application/zip", "format" => "zip"}]

  """
  def filter_zip(resources) do
    for resource <- resources, "#{resource["mime"]}#{resource["format"]}" =~ ~r/zip/i do
      %{resource | "mime" => "application/zip", "format" => "zip"}
    end
  end

  @doc """
  filter dataset with csv resources

  ## Examples
      iex> [%{"mime" => "text/csv", "format" => nil}]
      ...> |> ImportDataService.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => nil, "format" => "csv"}]
      ...> |> ImportDataService.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => nil, "format" => "CSV"}]
      ...> |> ImportDataService.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => "text/cv", "format" => nil}]
      ...> |> ImportDataService.filter_csv
      []

      iex> [%{"mime" => "text/csv", "format" => nil}, %{"mime" => "application/neptune", "format" => nil}]
      ...> |> ImportDataService.filter_csv
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
      ...> |> ImportDataService.has_csv?
      true

      iex> {:ok, %{headers: [{"Content-Type", "application/zip"}]}}
      ...> |> ImportDataService.has_csv?
      false

      iex> {:error, "pouet"}
      ...> |> ImportDataService.has_csv?
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
      ...> |> ImportDataService.get_url_from_csv()
      "http"

      iex> |> ImportDataService.get_url_from_csv()
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
      ...> |> ImportDataService.get_url_from_csv()
      {:ok, "http"}

      iex> "stop,lon,lat\\n1,48.8,2.3"
      ...> |> ImportDataService.get_url_from_csv()
      {:error, "No column file"}

      iex> "Donnees;format;Download\\r\\nHoraires des lignes TER;GTFS;https\\r\\n"
      ...> |> ImportDataService.get_url_from_csv()
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
  Get anomalies of a dataset

  ## Examples

      iex> %{"license" => "bliblablou", "download_url" => nil}
      ...> |> ImportDataService.get_anomalies()
      ["bad_license", "no_download_url"]

      iex> %{"license" => "odc-odbl", "download_url" => "http"}
      ...> |> ImportDataService.get_anomalies()
      []

  """
  def get_anomalies(dataset) do
    anomalies = dataset
                |> Map.get("anomalies", [])
                |> MapSet.new
    anomalies = if check_license(dataset) do
      MapSet.delete(anomalies, "bad_license")
    else
      MapSet.put(anomalies, "bad_license")
    end
    anomalies = if check_download_url(dataset) do
      MapSet.delete(anomalies, "no_download_url")
    else
      MapSet.put(anomalies, "no_download_url")
    end
    MapSet.to_list(anomalies)
  end

  @doc """
  Check for licence, returns ["bad_license"] if the licence is not "odc-odbl"
  or "fr-lo".

  ## Examples

      iex> ImportDataService.check_license(%{"license" => "bliblablou"})
      false

      iex> ImportDataService.check_license(%{"license" => "odc-odbl"})
      true

      iex> ImportDataService.check_license(%{"license" => "fr-lo"})
      true

  """
  def check_license(%{"license" => "odc-odbl"}), do: true
  def check_license(%{"license" => "fr-lo"}), do: true
  def check_license(_), do: false

  @doc """
  Check for download uri, returns ["no_download_url"] if there's no download_url

  ## Examples

      iex> ImportDataService.check_download_url(%{"download_url" => nil})
      false

      iex> ImportDataService.check_download_url(%{"download_url" => "http"})
      true

  """
  def check_download_url(%{"download_url" => nil}), do: false
  def check_download_url(%{"download_url" => _}), do: true

  def parse_date(date) when is_binary(date) do
    with {:ok, date} <- NaiveDateTime.from_iso8601(date) do
      date
      |> NaiveDateTime.to_date
      |> Date.to_string
    end
  end

  def parse_date(nil) do
    nil
  end
end
