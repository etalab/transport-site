defmodule Transport.Shared.ReqCustomCache do
  @moduledoc """
  A simple HTTP cache for `req` that do not use headers. If the file is not found
  on disk, the download will occur, otherwise response will be read from disk.

  At this point, this module is more designed for development use (with production data)
  than for production use (in particular, security implications of `:erlang.binary_to_term`
  and `:erlang.term_to_binary`).
  """
  require Logger

  def attach(%Req.Request{} = request, options \\ []) do
    request
    |> Req.Request.register_options([:custom_cache_dir])
    |> Req.Request.merge_options(options)
    |> Req.Request.append_request_steps(custom_cache: &request_local_cache_step/1)
    |> Req.Request.prepend_response_steps(custom_cache: &response_local_cache_step/1)
  end

  def request_local_cache_step(request) do
    # NOTE: for now, no expiration is supported, you'll have to wipe-out the cache folder manually
    # NOTE: race condition here, for parallel queries
    path = cache_path(request)

    if File.exists?(path) do
      # Logger.info("File found in cache (#{path})")
      {request, load_cache(path)}
    else
      request
    end
  end

  def response_local_cache_step({request, response}) do
    # NOTE: we'll need a way to let the caller customize which HTTP status codes must result
    # into caching vs not (e.g. rate limit 429 should ideally not be cached, while 404 should etc)
    path = cache_path(request)

    unless File.exists?(path) do
      Logger.info("Saving file to cache (#{path})")
      write_cache(path, response)
    end

    {request, response}
  end

  # https://github.com/wojtekmach/req/blob/102b9aa6c6ff66f00403054a0093c4f06f6abc2f/lib/req/steps.ex#L1268
  def cache_path(cache_dir, %{method: :get} = request) do
    cache_key =
      Enum.join(
        [
          request.url.host,
          Atom.to_string(request.method),
          :crypto.hash(:sha256, :erlang.term_to_binary(request.url))
          |> Base.encode16(case: :lower)
        ],
        "-"
      )

    Path.join(cache_dir, cache_key)
  end

  def cache_path(request) do
    cache_path(request.options[:custom_cache_dir], request)
  end

  # https://github.com/wojtekmach/req/blob/102b9aa6c6ff66f00403054a0093c4f06f6abc2f/lib/req/steps.ex#L1288-L1290
  def load_cache(path) do
    path |> File.read!() |> :erlang.binary_to_term()
  end

  # https://github.com/wojtekmach/req/blob/102b9aa6c6ff66f00403054a0093c4f06f6abc2f/lib/req/steps.ex#L1283-L1286
  def write_cache(path, response) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(response))
  end
end
