defmodule Datagouvfr.Client do
  @moduledoc """
  An API client for data.gouv.fr
  """

  alias Datagouvfr.Authentication
  alias OAuth2.{Client, Error, Request, Response}
  require Logger

  @type oauth2_response :: {:ok, any} | {:error, Error.t} | {:error, Response.t}
  @type response :: {:ok, any} | {:error, any}

  @spec base_url :: binary
  def base_url, do: Application.get_env(:oauth2, Authentication)[:site] |> Path.join("/api/1/")

  @spec get(%Plug.Conn{}, binary, Client.headers, Keyword.t) :: oauth2_response
  def get(%Plug.Conn{} = conn, url, headers \\ [], opts \\ []) do
    request(:get, conn, url, nil, headers, opts)
  end

  @spec get(binary | [binary]) :: response
  def get(path) when is_binary(path), do: request(:get, path)
  def get(path) when is_list(path), do: request(:get, path)

  @spec post(%Plug.Conn{}, binary, Client.body, Client.headers, Keyword.t) :: oauth2_response
  def post(%Plug.Conn{} = conn, url, body \\ "", headers \\ [], opts \\ []) do
    headers = default_content_type(headers)
    :post
    |> request(conn, url, body, headers, opts)
  end

  @spec delete(%Plug.Conn{}, binary, Client.headers, Keyword.t) :: oauth2_response
  def delete(%Plug.Conn{} = conn, url, headers \\ [], opts \\ []) do
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
  @spec request(atom, %Plug.Conn{}, binary, Client.body, Client.headers, Keyword.t) :: oauth2_response
  def request(method, %Plug.Conn{} = conn, url, body, headers, opts) do
    client = get_client(conn)
    url = process_url(url)
    opts = Keyword.put_new(opts, :timeout, 15_000)
    opts = Keyword.put_new(opts, :follow_redirect, true)
    method
    |> Request.request(client, url, body, headers, opts)
    |> post_process()
  end

  @spec request(atom, binary | [binary, ...]) :: response
  def request(method, path) do
    url = process_url(path)

    method
    |> HTTPoison.request(url, "", [], follow_redirect: true)
    |> post_process()
  end

  def get_client(conn) do
    conn.assigns
    |> Map.get(:token, nil)
    |> Authentication.client()
  end

  def post_process({:ok, %HTTPoison.Response{body: body} = response}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, body} -> post_process({:ok, %{body: body, status_code: response.status_code}})
      error -> post_process(error)
    end
  end

  @spec post_process({:error, any} | {:ok, %{body: any, status_code: integer}}) ::
          {:error, any} | {:ok, any}
  def post_process(response) do
    case response do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: 201, body: body}} -> {:ok, body}
      {:ok, %{status_code: _, body: body}} -> {:error, body}
      {:error, error} -> {:error, error}
    end
  end

  @spec process_url(binary | [binary]) :: any
  def process_url(path) when is_list(path), do: path |> Path.join |> process_url
  def process_url(path) when is_binary(path) do
    base_url()
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
