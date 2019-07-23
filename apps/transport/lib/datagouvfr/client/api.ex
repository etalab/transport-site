defmodule Datagouvfr.Client.API do
  @moduledoc """
  Request Datagouv API
  """
  require Logger

  @type response :: {:ok, any} | {:error, any}

  def post_process({:ok, %HTTPoison.Response{body: body} = response}) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, body} -> post_process({:ok, %{body: body, status_code: response.status_code}})
      error -> post_process(error)
    end
  end

  use Datagouvfr.Client

  @spec get(path, any(), any()) :: response
  def get(path, headers \\ [], options \\ []) when is_binary(path) or is_list(path) do
    request(:get, path, "", headers, options)
  end

  @spec post(path(), map() | any(), any(), boolean()) :: response
  def post(path, body, headers, blank \\ false)
  def post(path, body, headers, blank) when is_map(body) do
    case Jason.encode(body) do
      {:ok, body} ->
        post(path, body, headers, blank)
      {:error, error} ->
        Logger.error "Unable to parse JSON: #{error}"
        {:error, error}
    end
  end
  def post(path, body, headers, blank) when is_binary(path) or is_list(path) do
    headers = default_content_type(headers)

    if blank do
      Logger.debug fn -> "Post body: #{inspect body}" end
      Logger.debug fn -> "Post headers: #{inspect headers}" end
      {:ok, body}
    else
      request(:post, path, body, headers, [])
    end
  end

  @spec request(
          :delete | :get | :head | :options | :patch | :post | :put,
          path(),
          any(),
          any(),
          keyword
        ) :: response
  def request(method, path, body \\ "", headers \\ [], options \\ []) do
    url = process_url(path)

    method
    |> HTTPoison.request(url, body, headers, options)
    |> post_process()
  end
end
