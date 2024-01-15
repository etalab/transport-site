defmodule Transport.Req.Behaviour do
  @moduledoc """
  At time of writing, Req does not introduce a behaviour allowing us to "Mox", as described here:
  - https://github.com/wojtekmach/req/issues/143
  - https://github.com/wojtekmach/req/issues/246

  We introduce an "above-level" wrapper with only the specific bits we are interested in,
  in order to allow the use of Mox during tests.
  """

  # Ref: https://github.com/wojtekmach/req/blob/b40de7b7a0e7cc97a2c398ffcc42aa14962f3963/lib/req.ex#L545
  @type url() :: URI.t() | String.t()
  # Simplified version for our needs
  @callback get(url(), options :: keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  @callback get!(url() | keyword() | Req.Request.t(), options :: keyword()) :: Req.Response.t()
end

defmodule Transport.Req do
  @moduledoc """
  The wrapper for the behaviour, which acts as a central access point for `Req` operations.
  By default the implementation is itself & delegates to `Req` directly. During tests, a Mox
  # is configured instead
  """
  def impl, do: Application.get_env(:transport, :req_impl, __MODULE__)

  @behaviour Transport.Req.Behaviour
  defdelegate get(url, options), to: Req
  defdelegate get!(url, options), to: Req
end

# Experimental: a higher-level http client. In flux! Subject to change!
# Req allow better customisation and we should look into that.
defmodule Transport.HTTPClient do
  # TODO: pass an option to allow enabling the cache.
  # NOTE: `custom_cache_dir` is read but caching should be opt-in
  def get!(url, options) do
    options =
      Keyword.validate!(options, [
        :custom_cache_dir,
        :decode_body,
        :compressed,
        enable_cache: false
      ])

    url = URI.encode(url)
    req = Req.new()

    {enable_cache, options} = options |> Keyword.pop!(:enable_cache)

    req =
      if enable_cache do
        req |> Transport.Shared.ReqCustomCache.attach()
      else
        req
      end

    resp = Req.get!(req, options |> Keyword.merge(url: url))
    ensure_200_body(resp)
  end

  def ensure_200_body(resp) do
    %{body: body, status: 200} = resp
    body
  end
end
