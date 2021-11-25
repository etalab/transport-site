defmodule Opendatasoft.UrlExtractor do
  @moduledoc """
    Opendatasoft publishes a CSV file with an url to the GTFS.

    The name of the actual column which contains that url varies,
    because there is no clear specification. The module provides
    a heuristic to extract the actual url from the CSV,
    based on a list of potential names that have been seen in real
    life so far.
  """
  require Logger

  @separators [?;, ?,]
  @csv_headers [
    "Download",
    "download",
    "file",
    "Fichier",
    "fichier à télécharger",
    "url",
    "fichier",
    "fichier a telecharger",
    "fichier_a_telecharger"
  ]

  @spec get_csv_resources([any]) :: [any]
  def get_csv_resources(resources) do
    csv_resources = filter_csv(resources)

    with {:ok, bodys_and_resources} <- download_csv_list(csv_resources),
         {:ok, resources} <- get_resources_with_url_from_csv(bodys_and_resources) do
      resources
    else
      {:error, error} ->
        Logger.warn(" <message>  #{inspect(error)}")

        Enum.each(resources, fn resource ->
          Logger.warn(" <resource> #{resource["url"]}")
        end)

        []
    end
  end

  @doc """
  filter only the GTFS from an ODS csv file
  we filter out pdf and netex files,
  based only on with the title (eg. filename) since we do not have anything else.
  """
  @spec get_gtfs_csv_resources([any]) :: [any]
  def get_gtfs_csv_resources(resources) do
    csv_resources = resources |> get_csv_resources

    gtfs_files =
      csv_resources
      |> Enum.filter(fn r -> r["parsed_filename"] |> filename_matches_type?("gtfs") end)

    if Enum.empty?(gtfs_files) do
      # No GTFS files have been found, use the
      # legacy implementation rejecting PDF and NeTEx files
      csv_resources
      |> Enum.reject(fn r -> r["parsed_filename"] |> String.ends_with?(".pdf") end)
      |> Enum.reject(fn r ->
        r["parsed_filename"]
        |> String.downcase()
        |> String.contains?("netex")
      end)
    else
      gtfs_files
    end
  end

  @spec get_gtfs_rt_csv_resources([any]) :: [any]
  def get_gtfs_rt_csv_resources(resources) do
    resources
    |> get_csv_resources
    |> Enum.filter(fn r -> r["parsed_filename"] |> filename_matches_type?("gtfs-rt") end)
  end

  @spec get_netex_csv_resources([any]) :: [any]
  def get_netex_csv_resources(resources) do
    resources
    |> get_csv_resources
    |> Enum.filter(fn r -> r["parsed_filename"] |> filename_matches_type?("netex") end)
  end

  @spec filename_matches_type?(binary(), binary()) :: boolean()
  defp filename_matches_type?(filename, expected_type) do
    filename_to_type(filename) == expected_type
  end

  @doc """
  Infers a resource's type from its filename.

  ## Examples
      iex> UrlExtractor.filename_to_type("angers-gtfs-.zip")
      "gtfs"

      iex > UrlExtractor.filename_to_type("angers-gtfs-rt-alerts.json")
      "gtfs-rt"

      iex > UrlExtractor.filename_to_type("angers gtfs-rt.json")
      "gtfs-rt"

      iex > UrlExtractor.filename_to_type("angers gtfsrt.json")
      "gtfs-rt"

      iex > UrlExtractor.filename_to_type("description gtfs.pdf")
      nil

      iex > UrlExtractor.filename_to_type("réseau NeTEx.zip")
      "netex"

      iex > UrlExtractor.filename_to_type("foobar")
      nil
  """
  @spec filename_to_type(binary()) :: nil | binary()
  def filename_to_type(filename) do
    filename = String.downcase(filename)

    cond do
      String.ends_with?(filename, ".pdf") -> nil
      String.match?(filename, ~r/\bgtfs(-rt|rt| rt)\b/) -> "gtfs-rt"
      String.contains?(filename, "netex") -> "netex"
      String.contains?(filename, "gtfs") -> "gtfs"
      true -> nil
    end
  end

  @doc """
  filter csv http response

  ## Examples
      iex> %{headers: [{"Content-Type", "text/csv"}]}
      ...> |> UrlExtractor.has_csv?
      true

      iex> %{headers: [{"Content-Type", "application/zip"}]}
      ...> |> UrlExtractor.has_csv?
      false

      iex> {:error, "pouet"}
      ...> |> UrlExtractor.has_csv?
      false

  """
  @spec has_csv?(any()) :: boolean()
  def has_csv?(%{headers: headers}) do
    Enum.any?(headers, fn {k, v} ->
      k == "Content-Type" && String.contains?(v, "csv")
    end)
  end

  def has_csv?(_), do: false

  @spec download_csv_list([map()]) :: {:ok, [{binary(), map()}]} | {:error, binary()}
  defp download_csv_list(resources) when is_list(resources) do
    resources
    |> Enum.map(fn r -> {download_csv(r), r} end)
    |> Enum.filter(fn {http_response, _r} -> has_csv?(http_response) end)
    |> case do
      bodys = [_ | _] -> {:ok, Enum.map(bodys, fn {%{body: body}, r} -> {body, r} end)}
      [] -> {:error, "No csv found"}
    end
  end

  @spec download_csv(map()) :: map() | {:error, binary()}
  defp download_csv(%{"url" => url}) do
    case HTTPoison.get(url, [], hackney: [follow_redirect: true]) do
      {:ok, response = %{status_code: 200}} ->
        response

      {:ok, response} ->
        {:error, "Bad status code, needs 200, wants #{response.status_code}"}

      {:error, error} ->
        {:error, "impossible to download csv: #{inspect(error)}"}
    end
  end

  @doc """
  Get a download from a CSVs if it exists
  """
  @spec get_resources_with_url_from_csv([{binary, map()}]) ::
          {:ok, [map()]} | {:error, binary()}
  def get_resources_with_url_from_csv(bodies) when is_list(bodies) do
    bodies
    |> Enum.map(fn {body, r} ->
      body
      |> get_url_from_csv()
      |> Enum.map(fn url ->
        r
        |> Map.merge(%{
          "url" => url,
          "parsed_filename" => get_filename(url)
        })
      end)
    end)
    |> List.flatten()
    |> case do
      urls = [_ | _] -> {:ok, urls}
      [] -> {:error, "No url found"}
    end
  end

  @doc """
  Get a download from a CSV if it exists

  ## Examples
      iex> "name,file\\ntoulouse,http"
      ...> |> UrlExtractor.get_url_from_csv()
      ["http"]

      iex> "stop,lon,lat\\n1,48.8,2.3"
      ...> |> UrlExtractor.get_url_from_csv()
      []

      iex> "Donnees;format;Download\\r\\nHoraires des lignes TER;GTFS;https\\r\\n"
      ...> |> UrlExtractor.get_url_from_csv()
      ["https"]

  """
  @spec get_url_from_csv(binary()) :: [any()]
  def get_url_from_csv(body) do
    @separators
    |> Enum.map(&get_url_from_csv(&1, body))
    |> List.flatten()
  end

  @spec get_url_from_csv(binary(), binary()) :: [binary()]
  def get_url_from_csv(separator, body) do
    case StringIO.open(body) do
      {:ok, out} ->
        out
        |> IO.binstream(:line)
        |> CSV.decode(headers: true, separator: separator)
        |> Enum.map(&get_url_from_row/1)
        |> Enum.filter(&(&1 != nil))
    end
  rescue
    e in FunctionClauseError ->
      # A non UTF-8 encoded CSV file can make CSV.decode() raises a FunctionClauseError exception
      # we skip the file to allow the import to continue
      Sentry.capture_exception(e,
        stacktrace: __STACKTRACE__,
        extra: %{extra: "possibly trying to decode a non UTF-8 encoded csv resource"}
      )

      []
  end

  @spec get_url_from_row({:ok, map} | any | {:error, any}) :: binary | nil
  defp get_url_from_row({:ok, line}), do: get_url_from_csv_line(line)

  defp get_url_from_row({:error, error}) do
    Logger.error("error while parsing urlfrom row: #{inspect(error)}")
    nil
  end

  defp get_url_from_row(error) do
    Logger.error("unknown error while parsing urlfrom row: #{inspect(error)}")
    nil
  end

  @doc """
  Given a CSV row formatted as a map (keys as headers, values for values),
  this function attempts to detect potential candidates (`@csv_headers`) of columns
  # that should contain the target url.

  ## Examples

  If a well-known column is found, the module must return the url like this:

    iex> UrlExtractor.get_url_from_csv_line(%{"fichier_a_telecharger" => "http://the-url"})
    "http://the-url"

  On the other hand, if the column is unknown, the module will return `nil`:

    iex> UrlExtractor.get_url_from_csv_line(%{"fichié_a_download" => "http://the-url"})
    nil
  """
  @spec get_url_from_csv_line(map) :: binary
  def get_url_from_csv_line(line) do
    @csv_headers
    |> Enum.map(&Map.get(line, &1))
    |> Enum.filter(&(&1 != nil))
    |> case do
      [] -> nil
      [head | _] -> head
    end
  end

  @doc """
  filter dataset with csv resources

  ## Examples
      iex> [%{"mime" => "text/csv", "format" => nil}]
      ...> |> UrlExtractor.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => nil, "format" => "csv"}]
      ...> |> UrlExtractor.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => nil, "format" => "CSV"}]
      ...> |> UrlExtractor.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

      iex> [%{"mime" => "text/cv", "format" => nil}]
      ...> |> UrlExtractor.filter_csv
      []

      iex> [%{"mime" => "text/csv", "format" => nil}, %{"mime" => "application/neptune", "format" => nil}]
      ...> |> UrlExtractor.filter_csv
      [%{"mime" => "text/csv", "format" => "csv"}]

  """
  @spec filter_csv([map()]) :: [map()]
  def filter_csv(resources) do
    for resource <- resources, "#{resource["mime"]}#{resource["format"]}" =~ ~r/csv/i do
      %{resource | "mime" => "text/csv", "format" => "csv"}
    end
  end

  @spec get_filename(binary()) :: binary()
  defp get_filename(url) do
    httpoison_impl = Transport.Shared.Wrapper.HTTPoison.impl()

    with {:ok, %HTTPoison.Response{headers: headers}} <- httpoison_impl.head(url),
         {_, content} <- Enum.find(headers, fn {h, _} -> String.downcase(h) == "content-disposition" end),
         %{"filename" => filename} <- Regex.named_captures(~r/filename="(?<filename>.*)"/, content) do
      filename
    else
      _ -> url
    end
  end
end
