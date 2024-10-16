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

count_relevant_stop_places_per_resource = fn r ->
  IO.puts("Processing file #{r.id}")

  try do
    count =
      Transport.NeTEx.read_all_stop_places(r.local_path)
      |> Enum.flat_map(fn {_file, stops} -> stops end)
      # some stop places have no latitude in NeTEx
      |> Enum.reject(fn p -> is_nil(p[:latitude]) end)
      |> Enum.count()

    IO.puts("#{count} StopPlaces detected")
  rescue
    _ -> IO.puts("Som'thing bad happened")
  end
end

netex =
  df
  |> Task.async_stream(download_resource, max_concurrency: 10, timeout: 120_000)
  |> Stream.map(fn {:ok, result} -> result end)
  |> Stream.reject(&is_nil(&1))
  |> Task.async_stream(count_relevant_stop_places_per_resource, max_concurrency: 5, timeout: 60_000 * 5)
  |> Stream.run()
