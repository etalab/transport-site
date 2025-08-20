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

    @callback get!(url :: binary, headers :: headers(), options :: keyword()) :: any()
    @callback post!(url :: binary, headers :: headers(), body :: binary) :: any()

    def impl, do: Application.fetch_env!(:transport, :unlock_http_client)
  end

  defmodule FinchImpl do
    @moduledoc """
    A Finch-based implementation of the Client behaviour.
    """
    @behaviour Client

    # Implement HTTP GET with optional redirect support.
    #
    # If `max_redirects` is set to `0`, no redirect are allowed,
    # and a single HTTP call will ever be made.
    # If `max_redirects` is set to `1`, a maximum of two HTTP calls
    # will be issued, and only one redirect is allowed.
    #
    # A basic `RuntimeError("TooManyRedirects")` will be raised if
    # the limit of redirects is raised.
    def get!(url, headers, options \\ []) do
      max_redirects = Keyword.get(options, :max_redirects, 0)
      do_get!(url, headers, max_redirects + 1)
    end

    defp do_get!(_url, _headers, 0 = _max_redirects) do
      raise("TooManyRedirects")
    end

    # NOTE: supporting only minimal 302, since this is what data.gouv does for stable urls
    @redirect_status 302

    # In general, we want to avoid redirects when doing reverse proxy, since it
    # will introduce extra operational troubles. At time of writing and except
    # IRVE sources, no redirect is needed.
    #
    # For IRVE (aggregated) sources, though, we need to support data.gouv stable
    # urls, since it make the list of sources easier to maintain.
    #
    # Finch does not support redirects natively though, so we add support for
    # home-baked redirects.
    #
    # Ultimately, once Req hits v1.0, we will likely be better migrating this to Req,
    # which provides services on top of Finch.
    defp do_get!(url, headers, max_redirects) when is_integer(max_redirects) do
      {:ok, response} =
        :get
        |> Finch.build(url, headers)
        |> Finch.request(Unlock.Finch)

      response = %Response{
        body: response.body,
        status: response.status,
        headers: response.headers
      }

      if response.status == @redirect_status do
        [target_url] = for {"location", value} <- response.headers, do: value
        do_get!(target_url, headers, max_redirects - 1)
      else
        response
      end
    end

    def post!(url, headers, body) do
      {:ok, response} =
        :post
        |> Finch.build(url, headers, body)
        |> Finch.request(Unlock.Finch)

      %Response{
        body: response.body,
        status: response.status,
        headers: response.headers
      }
    end
  end
end
