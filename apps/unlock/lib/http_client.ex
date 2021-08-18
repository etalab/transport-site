defmodule Unlock.HTTP do
  @moduledoc """
  At time of writing, I could not find how to use Mox with Finch in a trivial way.
  I believe it can be done via mocking pools, but I was in a hurry, so it was easier
  to implement a simple wrapper that we have control of, at least for time being.
  """

  defmodule Response do
    @moduledoc """
    A simple wrapper we control for HTTP responses. It is actually almost identical to Finch's responses.
    """

    @enforce_keys [:body, :status, :headers]
    defstruct [:body, :status, :headers]
  end

  defmodule Client do
    @moduledoc """
    Behaviour and central access point for HTTP client operations.

    NOTE: the return type is incorrect, should be Response.t().
    """

    @typedoc """
    HTTP headers, with the same definition as Mint. See

    https://github.com/elixir-mint/mint/blob/main/lib/mint/types.ex
    """
    @type headers() :: [{header_name :: String.t(), header_value :: String.t()}]

    @callback get!(url :: binary, headers :: headers()) :: any()

    def impl, do: Application.fetch_env!(:unlock, :http_client)
  end

  defmodule FinchImpl do
    @moduledoc """
    A Finch-based implementation of the Client behaviour.
    """
    @behaviour Client

    def get!(url, headers) do
      {:ok, response} =
        :get
        |> Finch.build(url, headers)
        |> Finch.request(Unlock.Finch)

      %Response{
        body: response.body,
        status: response.status,
        headers: response.headers
      }
    end
  end
end
