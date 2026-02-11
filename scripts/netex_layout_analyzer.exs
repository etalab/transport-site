resources =
  DB.Resource
  |> DB.Repo.all()

# count
resources
|> Enum.count()
|> IO.inspect()

df =
  resources
  |> Enum.map(fn r ->
    %{
      id: r.id,
      url: r.url,
      title: r.title,
      unverified_format: r.format,
      description: r.description
    }
  end)
  |> Enum.filter(&(&1.unverified_format == "NeTEx"))

download_resource = fn r ->
  url = r.url
  file = Path.join("cache-dir", "resource-#{r.id}.dat")
  status_file = file <> ".status.json"

  unless File.exists?(status_file) do
    IO.puts("Saving #{url}")
    url = if String.contains?(url, "|"), do: URI.encode(url), else: url

    %{status: status} =
      Transport.HTTPClient.get!(url,
        decode_body: false,
        compressed: false,
        into: File.stream!(file)
      )

    File.write!(status_file, %{status: status} |> Jason.encode!())
  end

  %{"status" => status} = File.read!(status_file) |> Jason.decode!()

  r
  |> Map.put(:http_status, status)
  |> Map.put(:local_path, file)
end

hierarchy_level = fn file -> file |> String.split("/") |> Enum.count() end

dump_netex_files = fn r ->
  IO.puts("Processing file #{r.id}")

  url = "https://transport.data.gouv.fr/resources/#{r.id}"

  result =
    try do
      Transport.NeTEx.ArchiveParser.read_all_stop_places(r.local_path)
      |> Enum.map(fn {file, _stops} -> file end)
      |> Enum.reject(fn file -> String.ends_with?(file, "/") end)
      |> Enum.map(fn file -> [url, r.title, r.url, file, hierarchy_level.(file)] end)
    rescue
      _ ->
        IO.puts("Som'thing bad happened")
        []
    end

  NimbleCSV.RFC4180.dump_to_iodata(result)
end

output_file = "netex_layout_analysis.csv"

File.write(output_file, NimbleCSV.RFC4180.dump_to_iodata([~w(resource title url file hierarchy)]))

df
|> Task.async_stream(download_resource, max_concurrency: 10, timeout: 120_000)
|> Stream.map(fn {:ok, result} -> result end)
|> Stream.reject(&is_nil(&1))
|> Task.async_stream(dump_netex_files, max_concurrency: 5, timeout: 60_000 * 5)
|> Stream.map(fn {:ok, result} -> result end)
|> Stream.into(File.stream!(output_file, [:append, :utf8]))
|> Stream.run()
