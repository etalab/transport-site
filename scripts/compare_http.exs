#! mix run

defmodule Downloader do
  def url_hash(url) do
    :crypto.hash(:sha256, :erlang.term_to_binary(url))
    |> Base.encode16(case: :lower)
  end

  def get(:http_poison, url) do
    %HTTPoison.Response{status_code: status_code, body: body} =
      HTTPoison.get!(url, [], follow_redirect: true, timeout: 180_000, recv_timeout: 180_000)

    {status_code, body}
  end

  def get(:req, url) do
    # for now, do not ask the server for a compressed response, to mimic what's done by httpoison/hackney at the moment
    # https://hexdocs.pm/req/Req.Steps.html#compressed/1
    # also, do not decode the body as JSON (for instance)
    # TODO: ask for compressed, but decompress it, without decoding it as JSON
    %{status: status_code, body: body} =
      Req.get!(url, compressed: false, decode_body: false, receive_timeout: 180_000)

    {status_code, body}
  end

  def cache_dir, do: Path.join(__ENV__.file, "../cache-dir") |> Path.expand()

  def create_cache_dir do
    unless File.exists?(cache_dir()) do
      File.mkdir_p!(cache_dir())
    end
  end

  import Transport.LogTimeTaken, only: [log_time_taken: 2]

  def cached_get(client, url) do
    cache_key = ["test-http", client, url_hash(url)] |> Enum.join("-")
    file_cache = Path.join(cache_dir(), cache_key)
    IO.puts("#{client |> inspect} #{url} -> #{file_cache}")

    unless File.exists?(file_cache) do
      {status_code, body} = log_time_taken("#{client} - #{url}", fn -> get(client, url) end)
      unless status_code == 200 do
        IO.puts "Warn: #{client} got status_code=#{status_code}"
      end
      File.write!(file_cache, body)
    end

    File.read!(file_cache)
  end
end

Downloader.create_cache_dir()

defmodule ZipTools do
  def to_tmp_file(filename, content) do
    dir = System.tmp_dir!()
    tmp_file = Path.join(dir, filename)
    File.write!(tmp_file, content)
    tmp_file
  end

  # return the meta-data (list of files & checksums) of a given zip,
  # after writing it to a temp file since it's not currently possible
  # to read that from memory (https://github.com/akash-akya/unzip/issues/20)
  #
  # filtering out the `last_modified_datetime` because zenbus files are generated
  # on the fly and it would hinder the comparison.
  def get_zip_metadata(content) do
    filename = to_tmp_file("zip_meta", content)

    Transport.ZipMetaDataExtractor.extract!(filename)
    |> Enum.map(fn x -> x |> Map.delete(:last_modified_datetime) end)
  end
end

defmodule Script do
  def run!() do
    resources =
      DB.Resource
      |> DB.Repo.all()


    # TODO: investigate on resource 81159 (url query escaping???)
    resources
    # |> Enum.drop(1)
    # |> Enum.take(100)
    |> Enum.reject(fn r -> r.id == 80731 end) # timeout
    |> Enum.reject(fn r -> r.id in [7934, 8488, 80702, 9869] end) # missing eocd record in zip file
    #    |> Enum.filter(fn r -> r.id == 80856 end)
    |> Enum.with_index()
    |> Enum.each(fn x = {resource, index} ->
      IO.inspect({resource.id, resource.url, index})

      req_body = Downloader.cached_get(:req, resource.url)
      http_poison_body = Downloader.cached_get(:http_poison, resource.url)
      same = http_poison_body == req_body

      same =
        unless same do
          # TODO: verify that the format is GTFS before unzipping

          # in theory, we have zip files here, compare a good part of their metadata
          # to ensure the body has the same semantics
          meta_1 = ZipTools.get_zip_metadata(req_body)
          meta_2 = ZipTools.get_zip_metadata(http_poison_body)

          meta_1 == meta_2
        else
          same
        end

      unless same do
        IO.inspect(req_body)
        IO.inspect(http_poison_body)
        IO.puts("resource_id=#{resource.id |> inspect}")
        IO.puts(resource.url)

        IO.puts(
          "Files downloaded by req & http_poison are not the same (even after decompressing zips if they are zips)"
        )

        IO.puts "======== FAILURE - HALTING =========="
        System.halt()
      else 
        IO.puts "Files are the same"
      end
    end)
  end
end

Script.run!()

IO.puts "Leaving..."