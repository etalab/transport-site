defmodule Transport.Shared.Wrapper.Req do
  @moduledoc """
  A Req wrapper to facilitate the use of mocks.
  """
  def impl, do: Application.get_env(:transport, :req_impl)

  # Req apparently does not define a Behaviour that we can Mox directly, recommending
  # instead to mock "above" (via some wrapper) or "below" (via bypass)
  # See https://github.com/wojtekmach/req/issues/143
  defmodule Behaviour do
    # Ref: https://github.com/wojtekmach/req/blob/b40de7b7a0e7cc97a2c398ffcc42aa14962f3963/lib/req.ex#L545
    @callback get(url() | keyword() | Req.Request.t(), options :: keyword()) :: {:ok, Req.Response.t()} | {:error, Exception.t()}
  end
end
