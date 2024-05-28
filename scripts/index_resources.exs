resources =
  DB.Resource
  |> DB.Repo.all()

# count
resources
|> Enum.count()
|> IO.inspect()

# proportion de ressources par formats
defmodule StreamTools do
  def each_with_index(stream, function) do
    stream
    |> Stream.with_index()
    |> Stream.each(function)
    |> Stream.map(fn {item, _index} -> item end)
  end

  def show_one(stream, index) do
    StreamTools.each_with_index(stream, fn {item, i} ->
      if index == i do
        IO.puts("====== échantillon ======")
        IO.inspect(item, IEx.inspect_opts())
        IO.puts("")
      end
    end)
  end
end

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
  |> Explorer.DataFrame.new()

require Explorer.DataFrame

netex =
  df
  |> Explorer.DataFrame.filter(unverified_format == "NeTEx")
  |> Explorer.DataFrame.to_rows_stream()
  |> Task.async_stream(
    fn r ->
      url = r["url"]
      file = Path.join("cache-dir", "resource-#{r["id"]}.dat")
      status_file = file <> ".status.json"

      unless File.exists?(status_file) do
        IO.puts("Saving #{url}")
        url = if String.contains?(url, "|"), do: URI.encode(url), else: url

        %{status: status} =
          Transport.HTTPClient.get!(url, decode_body: false, compressed: false, into: File.stream!(file))

        File.write!(status_file, %{status: status} |> Jason.encode!())
      end

      %{"status" => status} = File.read!(status_file) |> Jason.decode!()

      r
      |> Map.put("http_status", status)
      |> Map.put("local_path", file)
    end,
    max_concurrency: 10,
    timeout: 120_000
  )
  |> Stream.map(fn {:ok, result} -> result end)
  |> Stream.reject(&is_nil(&1))
  |> Task.async_stream(
    fn r ->
      IO.puts("Processing file #{r["id"]}")

      try do
        resource = DB.Repo.get_by!(DB.Resource, id: r["id"])

        # temporary caching
        unless resource.search_points do
          coordinates =
            Transport.NeTEx.read_all_stop_places(r["local_path"])
            |> Enum.flat_map(fn {_file, stops} -> stops end)
            # some stop places have no latitude in NeTEx
            |> Enum.reject(fn p -> is_nil(p[:latitude]) end)
            |> Enum.map(fn %{latitude: lat, longitude: lon} -> {lon, lat} end)

          search_points = %Geo.MultiPoint{coordinates: coordinates, srid: 4326}

          DB.Repo.get_by!(DB.Resource, id: r["id"])
          |> DB.Resource.changeset(%{search_points: search_points})
          |> DB.Repo.update!()
        end
      rescue
        e -> IO.puts("Som'thing bad happened")
      end
    end,
    max_concurrency: 5,
    timeout: 60_000 * 5
  )
  |> Stream.run()
