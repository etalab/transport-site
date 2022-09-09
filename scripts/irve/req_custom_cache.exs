defmodule CustomCache do
  @moduledoc """
  A simple HTTP cache for `req` that do not use headers. If the file is not found
  on disk, the download will occur, otherwise response will be read from disk.
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
    # TODO: handle a form of expiration - for now it is acceptable to wipe out the whole folder manually for me
    # NOTE: race condition here, for parallel queries
    if File.exists?(path = cache_path(request)) do
      Logger.info("File found in cache (#{path})")
      {request, load_cache(path)}
    else
      request
    end
  end

  def response_local_cache_step({request, response}) do
    unless File.exists?(path = cache_path(request)) do
      if response.status == 200 do
        Logger.info("Saving file to cache (#{path})")
        write_cache(path, response)
      else
        Logger.info("Status is #{response.status}, not saving file to disk")
      end
    end

    {request, response}
  end

  # https://github.com/wojtekmach/req/blob/102b9aa6c6ff66f00403054a0093c4f06f6abc2f/lib/req/steps.ex#L1268
  def cache_path(cache_dir, request = %{method: :get}) do
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
