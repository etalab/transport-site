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
  @callback get(url()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  @callback get(url(), options :: keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}

  @callback get!(url() | keyword() | Req.Request.t()) :: Req.Response.t()
  @callback get!(url() | keyword() | Req.Request.t(), options :: keyword()) :: Req.Response.t()

  @callback request(request :: Req.Request.t() | keyword()) ::
              {:ok, Req.Response.t()} | {:error, Exception.t()}
  @callback request(request :: Req.Request.t() | keyword(), options :: keyword()) ::
              {:ok, Req.Response.t()} | {:error, Exception.t()}

  @callback delete(url() | keyword() | Req.Request.t()) ::
              {:ok, Req.Response.t()} | {:error, Exception.t()}
  @callback delete(url() | keyword() | Req.Request.t(), options :: keyword()) ::
              {:ok, Req.Response.t()} | {:error, Exception.t()}
end

defmodule Transport.Req do
  @moduledoc """
  The wrapper for the behaviour, which acts as a central access point for `Req` operations.
  By default the implementation is itself & delegates to `Req` directly. During tests, a Mox
  # is configured instead
  """
  def impl, do: Application.get_env(:transport, :req_impl, __MODULE__)

  @behaviour Transport.Req.Behaviour
  defdelegate get(url, options \\ []), to: Req
  defdelegate get!(url, options \\ []), to: Req
  defdelegate request(request, options \\ []), to: Req
  defdelegate delete(request, options \\ []), to: Req
end

defmodule Transport.HTTPClient do
  @moduledoc """
  An experimental Req higher-level wrapper client that we can Mox, supporting
  easy opt-in cache enabling (crucial for large HTTP development locally).
  """

  def get!(url, options) do
    {req, options} = setup_cache(options)

    Transport.Req.impl().get!(req, options |> Keyword.merge(url: url))
  end

  def get(url, options) do
    {req, options} = setup_cache(options)

    Transport.Req.impl().get(req, options |> Keyword.merge(url: url))
  end

  defp setup_cache(options) do
    options =
      Keyword.validate!(options, [
        :custom_cache_dir,
        :decode_body,
        :compressed,
        :into,
        enable_cache: false
      ])

    req = Req.new()

    {enable_cache, options} = options |> Keyword.pop!(:enable_cache)

    if enable_cache do
      {req |> Transport.Shared.ReqCustomCache.attach(), options}
    else
      {req, options}
    end
  end
end
