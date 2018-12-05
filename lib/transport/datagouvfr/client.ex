defmodule Transport.Datagouvfr.Client do
  @moduledoc """
  An API client for data.gouv.fr
  """

  alias OAuth2.Client, as: OAuth2Client
  alias OAuth2.{Error, Request, Response}
  alias Transport.Datagouvfr.Authentication
  require Logger

  @base_url Application.get_env(:oauth2, Authentication)[:site] |> Path.join("/api/1/")

  @spec get_request(%Plug.Conn{}, binary, OAuth2Client.headers, Keyword.t)
                    :: {:ok, OAuth2.Response.t} | {:error, Error.t}
  def get_request(%Plug.Conn{} = conn, url, headers \\ [], opts \\ []) do
    Transport.Datagouvfr.Client.request(:get, conn, url, nil, headers, opts)
  end

  @spec post_request(%Plug.Conn{}, binary, OAuth2Client.body,
                    OAuth2Client.headers, Keyword.t)
                    :: {:ok, Response.t} | {:error, Error.t}
  def post_request(%Plug.Conn{} = conn, url, body \\ "", headers \\ [], opts \\ []) do
    headers = default_content_type(headers)
    :post
    |> request(conn, url, body, headers, opts)
  end

  @spec delete_request(%Plug.Conn{}, binary, OAuth2Client.headers, Keyword.t)
                    :: {:ok, Response.t} | {:error, Error.t}
  def delete_request(%Plug.Conn{} = conn, url, headers \\ [], opts \\ []) do
    headers = default_content_type(headers)
    :delete
    |> request(conn, url, nil, headers, opts)
  end

  #credo:disable-for-lines:9
  @doc """
  We disable for now the credo test because the arity is to high
  TODO: add a Transport.Request module to lower the arity and make this
  module clearer
  """
  @spec request(atom, %Plug.Conn{}, binary, OAuth2Client.body,
                OAuth2Client.headers, Keyword.t)
                :: {:ok, Response.t} | {:error, Response.t} | {:error, Error.t}
  def request(method, %Plug.Conn{} = conn, url, body, headers, opts) do
    client = get_client(conn)
    url = process_url(url)
    opts = Keyword.put_new(opts, :timeout, 15_000)
    opts = Keyword.put_new(opts, :follow_redirect, true)
    method
    |> Request.request(client, url, body, headers, opts)
    |> post_process_request()
  end

  def get_client(conn) do
    conn.assigns
    |> Map.get(:token, nil)
    |> Authentication.client()
  end

  def post_process_request(response) do
    case response do
      {:ok, %OAuth2.Response{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %OAuth2.Response{status_code: 201, body: body}} -> {:ok, body}
      {:ok, %OAuth2.Response{status_code: _, body: body}} -> {:error, body}
      {:error, error} -> {:error, error}
    end
  end

  def get_discussions(conn, id) do
    conn
    |> get_request("/discussions?for=#{id}", [], follow_redirect: true)
    |> case do
      {:ok, %{"data" => data}} -> data
      error ->
        Logger.error("When fetching discussions for id #{id}: #{error}")
        []
    end
  end

  def get_community_ressources(conn, id) do
    conn
    |> get_request("/datasets/community_resources/?dataset=#{id}", [])
    |> case do
      {:ok, %{"data" => data}} -> data
      error ->
        Logger.error("When getting community_ressources for id #{id}: #{error}")
        []
    end
  end

  def process_url(path) when is_list(path), do: path |> Path.join |> process_url
  def process_url(path) do
    @base_url
    |> Path.join(path)
    |> URI.parse
    |> add_trailing_slash
  end

  # private

  defp add_trailing_slash(uri) when is_map(uri) do
    %URI{uri | path: add_trailing_slash(uri.path)}
    |> to_string
  end

  defp add_trailing_slash(path) do
    case path |> String.slice(-1..-1) do
      "/" -> path
      _ -> path <> "/"
    end
  end

  defp default_content_type(headers) do
    case Enum.any?(headers, &content_type?(&1)) do
      true -> headers
      false -> [{"content-type", "application/json"} | headers]
    end
  end

  defp content_type?(header) do
    header
    |> elem(0)
    |> String.downcase
    |> Kernel.==("content-type")
  end
end
