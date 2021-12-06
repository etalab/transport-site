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

    @callback get!(url :: binary, headers :: headers(), options :: Keyword.t()) :: any()

    def impl, do: Application.fetch_env!(:unlock, :http_client)
  end

  defmodule FinchImpl do
    @moduledoc """
    A Finch-based implementation of the Client behaviour.
    """
    @behaviour Client
    @redirect_codes [301, 302, 303, 307, 308]
    @max_redirections 5

    def get!(url, headers, options \\ []) do
      {:ok, response} =
        :get
        |> Finch.build(url, headers)
        |> Finch.request(Unlock.Finch)

      process_response(response, url, headers, options)
    end

    defp process_response(response, url, headers, options) do
      follow_redirect = Keyword.get(options, :follow_redirect, false)
      max_redirections = Keyword.get(options, :max_redirections, @max_redirections)
      is_redirect = Enum.member?(@redirect_codes, response.status)

      if is_redirect and follow_redirect do
        if max_redirections < 0 do
          raise RuntimeError, "exceeded max redirections for #{url}"
        end

        location =
          response.headers |> Enum.into(%{}, fn {k, v} -> {String.downcase(k), v} end) |> Map.fetch!("location")

        uri = URI.parse(location)

        next_url =
          cond do
            is_nil(uri.scheme) -> URI.merge(URI.parse(url), uri) |> to_string()
            true -> uri |> to_string()
          end

        get!(next_url, headers, options |> Keyword.put(:max_redirections, max_redirections - 1))
      else
        %Response{
          body: response.body,
          status: response.status,
          headers: response.headers
        }
      end
    end
  end
end
