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
    @callback get!(url :: binary, headers :: list()) :: Response.t()

    def impl(), do: Application.fetch_env!(:unlock, :http_client)
  end

  defmodule FinchImpl do
    @behaviour Client

    def get!(url, headers) do
      {:ok, response} =
        Finch.build(:get, url, headers)
        |> Finch.request(Unlock.Finch)

      %Response{
        body: response.body,
        status: response.status,
        headers: response.headers
      }
    end
  end
end
