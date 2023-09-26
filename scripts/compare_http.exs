#! mix run

defmodule Downloader do
  def url_hash(url) do
    :crypto.hash(:sha256, :erlang.term_to_binary(url))
    |> Base.encode16(case: :lower)
  end

  def get(:http_poison, url) do
    %HTTPoison.Response{status_code: 200, body: body} =
      HTTPoison.get!(url, [], follow_redirect: true, timeout: 180_000, recv_timeout: 180_000)

    body
  end

  def get(:req, url) do
    # for now, do not ask the server for a compressed response, to mimic what's done by httpoison/hackney at the moment
    # https://hexdocs.pm/req/Req.Steps.html#compressed/1
    # also, do not decode the body as JSON (for instance)
    # TODO: ask for compressed, but decompress it, without decoding it as JSON
    %{status: 200, body: body} = Req.get!(url, compressed: false, decode_body: false, receive_timeout: 180_000)
    body
  end

  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

  def create_cache_dir do
    unless File.exists?(cache_dir()) do
      File.mkdir_p!(cache_dir())
    end
  end

  def cached_get(client, url) do
    cache_key = ["test-http", client, url_hash(url)] |> Enum.join("-")
    file_cache = Path.join(cache_dir(), cache_key)
    IO.puts("#{client |> inspect} #{url} -> #{file_cache}")

    unless File.exists?(file_cache) do
      body = get(client, url)
      File.write!(file_cache, body)
    end

    File.read!(file_cache)
  end
end

Downloader.create_cache_dir()

defmodule Script do
  def run!() do
    resources =
      DB.Resource
      |> DB.Repo.all()

    resources
    |> Enum.drop(1)
    |> Enum.take(100)
    |> Enum.reject(fn r -> r.id == 80731 end)
    #    |> Enum.filter(fn r -> r.id == 80856 end)
    |> Enum.with_index()
    |> Enum.each(fn x = {resource, index} ->
      IO.inspect({resource.id, resource.url, index})

      req_body = Downloader.cached_get(:req, resource.url)
      http_poison_body = Downloader.cached_get(:http_poison, resource.url)
      same = http_poison_body == req_body
      IO.inspect(same)

      unless same do
        IO.inspect(req_body)
        IO.inspect(http_poison_body)
        IO.puts("resource_id=#{resource.id |> inspect}")
        IO.puts(resource.url)
        System.halt()
      end
    end)
  end
end

Script.run!()

# url =
#   "https://static.data.gouv.fr/resources/amenagements-cyclables-france-metropolitaine/20220709-004511/france-20220708.geojson"

# # debugging
# # :hackney_trace.enable(:max, :io)

# import Transport.LogTimeTaken, only: [log_time_taken: 2]

# # log_time_taken("download with http poison", fn ->
# #   h1 = Downloader.get(:http_poison, url)
# # end)

# log_time_taken("download with req", fn ->
#   h2 = Downloader.get(:req, url)
# end)

# # File.write!("something.gz", h2)

# # IO.inspect(h2)
