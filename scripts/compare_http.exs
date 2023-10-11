#! mix run

# NOTE: very dirty script I've used to compare behaviours of HTTPoison & Req on a largish number of files (~700)
# before migrating clients.

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
    # Note for real implementation: it would be better to ask for compressed,
    # but decompress it, without decoding it as JSON
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

  def cached_get(client, url, message \\ "") do
    cache_key = ["test-http", client, url_hash(url)] |> Enum.join("-")
    file_cache = Path.join(cache_dir(), cache_key)
    file_cache_status = file_cache <> ".status"

    unless File.exists?(file_cache) do
      IO.puts("File does not exist #{file_cache}... (#{url} #{message})")
      {status_code, body} = get(client, url)

      File.write!(file_cache, body)
      File.write!(file_cache_status, status_code |> to_string)
    end

    {
      File.read!(file_cache_status),
      File.read!(file_cache)
    }
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
  def get_zip_metadata(:old, content) do
    filename = to_tmp_file("zip_meta", content)

    # NOTE: it would be better to delete the tempfile after analysis
    Transport.ZipMetaDataExtractor.extract!(filename)
    |> Enum.map(fn x -> x |> Map.take([:file_name]) end)
  end

  def get_zip_metadata(content) do
    filename = to_tmp_file("zip_meta", content)
    {output, exit_code} = System.cmd("unzip", ["-Z1", filename], stderr_to_stdout: true)

    cond do
      exit_code == 0 ->
        output |> String.split("\n") |> Enum.sort()

      output =~ ~r/cannot find zipfile directory|signature not found/ ->
        :corrupt

      true ->
        raise "should not happen"
    end
  end
end

defmodule Script do
  require Logger

  def run!() do
    task = fn resource ->
      resp_1 =
        try do
          {status_code, body} = Downloader.cached_get(:http_poison, resource.url, "resource_id=#{resource.id}")
          {:ok, {status_code, body}}
        rescue
          e ->
            Logger.error("Error for resource_id=#{resource.id} #{resource.url} - #{e |> inspect}")
            {:error, e}
        end

      resp_2 =
        try do
          url = resource.url |> String.replace("|", "|" |> URI.encode())
          {status_code, body} = Downloader.cached_get(:req, url, "resource_id=#{resource.id}")
          {:ok, {status_code, body}}
        rescue
          e ->
            Logger.error("Error for resource_id=#{resource.id} #{resource.url} - #{e |> inspect}")
            {:error, e}
        end

      status_1 = resp_1 |> elem(1) |> elem(0)
      status_2 = resp_2 |> elem(1) |> elem(0)

      cond do
        status_1 != status_2 ->
          IO.puts("warn: http_poison=#{status_1} req=#{status_2}")

        true ->
          nil
      end

      same = resp_1 == resp_2

      unless same do
        if resource.format == "GTFS" do
          {:ok, {status_code_1, body_1}} = resp_1
          {:ok, {status_code_2, body_2}} = resp_2

          try do
            meta_1 = ZipTools.get_zip_metadata(body_1)
            meta_2 = ZipTools.get_zip_metadata(body_2)

            cond do
              meta_1 == :corrupt && meta_2 == :corrupt ->
                :both_corrupt_gtfs

              meta_1 == :corrupt && meta_2 != :corrupt ->
                :http_poison_corrupt

              meta_1 != :corrupt && meta_2 == :corrupt ->
                :req_corrupt

              meta_1 != :corrupt && meta_2 != :corrupt && meta_1 == meta_2 ->
                :same_gtfs_meta

              meta_1 != meta_2 ->
                IO.puts("==============")
                IO.inspect(meta_1)
                IO.inspect(meta_2)
                :different_gtfs
            end
          rescue
            e ->
              IO.puts("Compare failed: #{e |> inspect}")
              :compare_failed_gtfs
          end
        else
          :different
        end
      else
        :same
      end
    end

    Transport.Jobs.ResourceHistoryAndValidationDispatcherJob.resources_to_historise()
    #    |> Enum.reject(&(&1.dataset_id == 641)) # https://transport.data.gouv.fr/datasets/amenagements-cyclables-france-metropolitaine
    |> Task.async_stream(
      task,
      # not too high initially or HTTPoison will raise errors
      max_concurrency: 50,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, r} -> r end)
    |> Enum.frequencies()
    |> IO.inspect(IEx.inspect_opts())
  end

  def show_large do
    task = fn resource ->
      {status_code, body} = Downloader.cached_get(:http_poison, resource.url, "resource_id=#{resource.id}")
      {resource.dataset_id, body |> byte_size()}
    end

    Transport.Jobs.ResourceHistoryAndValidationDispatcherJob.resources_to_historise()
    |> Task.async_stream(
      task,
      max_concurrency: 10,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, x} -> x end)
    |> Enum.filter(fn {_id, size} -> size > 100_000_000 end)
    |> Enum.map(fn {id, s} -> id end)
    |> Enum.uniq()
    |> Enum.each(&IO.inspect(&1))
  end
end

# Script.run!()
# Script.show_large()

IO.puts("Leaving...")
