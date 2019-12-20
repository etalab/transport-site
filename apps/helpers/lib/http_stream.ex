defmodule HTTPStream do
  @moduledoc """
  Gives you a stream from an URL
  """
  require Logger
  alias Mint.HTTP

  def get(url) do
    Stream.resource(
      fn -> request(url) end,
      &handle_async_resp/1,
      fn
        nil ->
          []

        conn ->
          HTTP.close(conn)
      end
    )
  end

  def request(url) do
    uri = URI.parse(url)

    with {:ok, conn} <- HTTP.connect(String.to_atom(uri.scheme), uri.host, uri.port),
         {:ok, conn, _ref} <- HTTP.request(conn, "GET", merge_path(uri), []) do
      conn
    else
      {:error, conn, reason} ->
        Logger.error(fn -> inspect(reason) end)
        conn

      {:error, error} ->
        Logger.error(fn -> inspect(error) end)
        nil
    end
  end

  def merge_path(%URI{path: path, query: query}) when is_nil(query), do: path
  def merge_path(%URI{path: path, query: query}), do: path <> "?" <> query

  defp handle_async_resp({:end, conn}), do: {:halt, conn}
  defp handle_async_resp(nil), do: {:halt, nil}

  defp handle_async_resp(conn) do
    receive do
      message ->
        case HTTP.stream(conn, message) do
          :unknown ->
            Logger.error("Unknown error")
            {:halt, conn}

          {:ok, conn, responses} ->
            responses
            |> Enum.map(&handle_response/1)
            |> Enum.reject(&is_nil/1)
            |> Enum.reverse()
            |> case do
              [:done | r] -> {Enum.reverse(r), {:end, conn}}
              r -> {Enum.reverse(r), conn}
            end
        end
    after
      2000 ->
        Logger.error("Timeout")
        {:halt, nil}
    end
  end

  def handle_response({:data, _ref, data}), do: data
  def handle_response({:done, _ref}), do: :done
  def handle_response(_), do: nil
end
