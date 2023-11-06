defmodule Transport.Req.Behaviour do
  # Req apparently does not define a Behaviour that we can Mox directly, recommending
  # instead to mock "above" (via some wrapper) or "below" (via bypass)
  # See https://github.com/wojtekmach/req/issues/143
  # Ref: https://github.com/wojtekmach/req/blob/b40de7b7a0e7cc97a2c398ffcc42aa14962f3963/lib/req.ex#L545
  @type url() :: URI.t() | String.t()
  # Simplified version for our needs
  @callback get(url(), options :: keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
end

defmodule Transport.Req do
  def impl, do: Application.get_env(:transport, :req_impl, __MODULE__)

  @behaviour Transport.Req.Behaviour
  defdelegate get(url, options), to: Req
end
