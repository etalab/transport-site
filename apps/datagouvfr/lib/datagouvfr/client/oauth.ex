defmodule Datagouvfr.Client.OAuth do
  @moduledoc """
  Request Datagouvfr API with OAuth
  """
  use Datagouvfr.Client

  alias Datagouvfr.Authentication
  alias OAuth2.{Client, Error, Request, Response}

  require Logger

  @type oauth2_response :: {:ok, any} | {:error, Error.t()} | {:error, Response.t()}

  @spec get(Plug.Conn.t() | OAuth2.AccessToken.t(), path, Client.headers(), Keyword.t()) :: oauth2_response
  def get(conn_or_token, path, headers \\ [], opts \\ []) do
    request(:get, conn_or_token, path, nil, headers, opts)
  end

  @spec post(Plug.Conn.t(), path, Client.body(), Client.headers(), Keyword.t()) :: oauth2_response
  def post(%Plug.Conn{} = conn, path, body \\ "", headers \\ [], opts \\ []) do
    headers = default_content_type(headers)

    request(:post, conn, path, body, headers, opts)
  end

  @spec put(Plug.Conn.t(), path, Client.body(), Client.headers(), Keyword.t()) :: oauth2_response
  def put(%Plug.Conn{} = conn, path, body \\ "", headers \\ [], opts \\ []) do
    headers = default_content_type(headers)

    request(:put, conn, path, body, headers, opts)
  end

  @spec delete(Plug.Conn.t(), path, Client.headers(), Keyword.t()) :: oauth2_response
  def delete(%Plug.Conn{} = conn, path, headers \\ [], opts \\ []) do
    headers = default_content_type(headers)

    :delete
    |> request(conn, path, nil, headers, opts)
  end

  # credo:disable-for-lines:9
  @doc """
  We disable for now the credo test because the arity is to high
  TODO: add a Transport.Request module to lower the arity and make this
  module clearer
  """
  @spec request(atom, Plug.Conn.t() | OAuth2.AccessToken.t(), path, Client.body(), Client.headers(), Keyword.t()) ::
          oauth2_response
  def request(method, conn_or_token, path, body, headers, opts) do
    client = get_client(conn_or_token)
    url = process_url(path)
    # See Hackney options
    # https://github.com/benoitc/hackney/blob/master/doc/hackney.md
    opts = Keyword.put_new(opts, :recv_timeout, 15_000)
    opts = Keyword.put_new(opts, :follow_redirect, true)
    Logger.debug(fn -> "Request to: #{path}" end)
    Logger.debug(fn -> "Body: #{inspect(body)}" end)
    Logger.debug(fn -> "Headers: #{inspect(headers)}" end)
    Logger.debug(fn -> "Options: #{inspect(opts)}" end)

    method
    |> Request.request(client, url, body, headers, opts)
    |> post_process()
  end

  @spec get_client(Plug.Conn.t()) :: OAuth2.Client.t()
  def get_client(%Plug.Conn{} = conn) do
    conn.assigns
    |> Map.get(:datagouv_token, nil)
    |> Authentication.client()
  end

  @spec get_client(OAuth2.AccessToken.t()) :: OAuth2.Client.t()
  def get_client(%OAuth2.AccessToken{} = token), do: Authentication.client(token)
end
