defmodule Datagouvfr.Client.API do
  @moduledoc """
  Request Datagouv API
  """
  require Logger
  use Datagouvfr.Client

  @type response :: {:ok, any} | {:error, any}
  @type method :: :delete | :get | :head | :options | :patch | :post | :put

  # HTTP client injection. Allow mock injection in tests
  defp http_client, do: Application.fetch_env!(:transport, :httpoison_impl)

  def api_key_headers do
    {"X-API-KEY", Application.get_env(:transport, :datagouvfr_apikey)}
  end

  @spec decode_body({:ok, %HTTPoison.Response{body: binary()}}) :: {:ok, map()} | {:error, any()}
  def decode_body({:ok, %HTTPoison.Response{body: "", status_code: status_code}}),
    do: {:ok, %{body: %{}, status_code: status_code}}

  def decode_body({:ok, %HTTPoison.Response{body: body, status_code: status_code}})
      when is_binary(body) do
    case Jason.decode(body) do
      {:ok, decoded_body} -> {:ok, %{body: decoded_body, status_code: status_code}}
      {:error, error} -> {:error, error}
    end
  end

  def decode_body({:error, %HTTPoison.Error{} = error}) do
    {:error, error}
  end

  @spec get(path, [{binary(), binary()}], keyword()) :: response
  def get(path, headers \\ [], options \\ []) when is_binary(path) or is_list(path) do
    request(:get, path, "", headers, options)
  end

  @spec post(path(), any(), [{binary(), binary()}], boolean()) :: response
  def post(path, body, headers, blank \\ false)

  def post(path, body, headers, blank) when is_map(body) do
    case Jason.encode(body) do
      {:ok, body} ->
        post(path, body, headers, blank)

      {:error, error} ->
        Logger.error("Unable to parse JSON: #{error}")
        {:error, error}
    end
  end

  def post(path, body, headers, blank) when is_binary(path) or is_list(path) do
    headers = default_content_type(headers)

    if blank do
      Logger.debug(fn -> "Post body: #{inspect(body)}" end)
      Logger.debug(fn -> "Post headers: #{inspect(headers)}" end)
      {:ok, body}
    else
      request(:post, path, body, headers, [])
    end
  end

  @spec delete(path, [{binary(), binary()}], keyword()) :: response
  def delete(path, headers \\ [], options \\ []) when is_binary(path) do
    request(:delete, path, "", headers, options)
  end

  @spec request(
          :delete | :get | :head | :options | :patch | :post | :put,
          path(),
          any(),
          [{binary(), binary()}],
          keyword
        ) :: response
  def request(method, path, body \\ "", headers \\ [], options \\ []) do
    url = process_url(path)
    request_url(method, url, body, headers, options)
  end

  @spec request_url(
          method(),
          path(),
          any(),
          [{binary(), binary()}],
          keyword
        ) :: response
  defp request_url(method, url, body \\ "", headers \\ [], options \\ []) do
    options = Keyword.put_new(options, :follow_redirect, true)

    method
    |> http_client().request(url, body, headers, options)
    |> decode_body()
    |> post_process()
  end

  @spec stream(path(), method()) :: Enumerable.t()
  def stream(path, method \\ :get) do
    next_fun = fn
      nil ->
        {:halt, nil}

      url ->
        case request_url(method, url) do
          {:ok, body} ->
            next_page = Map.get(body, "next_page", nil)
            {[{:ok, body}], next_page}

          {:error, error} ->
            {[{:error, error}], nil}
        end
    end

    Stream.resource(
      fn -> process_url(path) end,
      next_fun,
      fn _ -> nil end
    )
  end

  @spec fetch_all_pages!(path(), method()) :: [any()]
  def fetch_all_pages!(path, method \\ :get) do
    path
    |> Datagouvfr.Client.API.stream(method)
    |> Stream.flat_map(fn element ->
      case element do
        {:ok, %{"data" => data}} ->
          data

        {:ok, response} ->
          raise "Request was ok but the response didn't contain data. Response : #{response}"

        {:error, %{reason: reason}} ->
          raise reason

        {:error, error} ->
          raise error
      end
    end)
    |> Enum.to_list()
  end

  @spec fetch_all_pages(path(), method()) :: {:ok, [any()]} | {:error, any()}
  def fetch_all_pages(path, method \\ :get) do
    {:ok, fetch_all_pages!(path, method)}
  rescue
    error ->
      Logger.error(error)
      {:error, error}
  end
end
