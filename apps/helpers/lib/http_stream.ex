defmodule HTTPStream do
  @moduledoc """
  Gives you a stream from an URL
  """
  require Logger
  alias Mint.HTTP

  @spec get(binary()) :: ({:cont, any()} | {:halt, any()} | {:suspend, any()}, any() -> any())
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

  @spec request(binary() | URI.t()) :: nil | Mint.HTTP.t()
  def request(url) do
    uri = URI.parse(url)

    with {:ok, conn} <- HTTP.connect(String.to_atom(uri.scheme), uri.host, uri.port),
         {:ok, conn, _ref} <- HTTP.request(conn, "GET", merge_path(uri), [], "") do
      conn
    else
      {:error, conn, reason} ->
        Logger.error("Error in http request of #{url} : #{inspect(reason)}")
        conn

      {:error, error} ->
        Logger.error("Error in http request of #{url} : #{inspect(error)}")
        nil
    end
  end

  @spec merge_path(URI.t()) :: binary()
  def merge_path(%URI{path: path, query: nil}), do: path
  def merge_path(%URI{path: path, query: query}), do: "#{path}?#{query}"

  @spec handle_async_resp(any()) :: any()
  defp handle_async_resp({:end, conn}), do: {:halt, conn}
  defp handle_async_resp(nil), do: {:halt, nil}

  defp handle_async_resp(conn) do
    receive do
      message ->
        case HTTP.stream(conn, message) do
          :unknown ->
            Logger.error("Unknown error in stream")
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
        Logger.error("Timeout in http stream")
        {:halt, nil}
    end
  end

  @spec handle_response(keyword()) :: any()
  def handle_response({:data, _ref, data}), do: data
  def handle_response({:done, _ref}), do: :done
  # NOTE: as seen in https://github.com/elixir-mint/mint#usage,
  # :headers and :status can also be seen, and are currently
  # ignored. I do not know if this is a problem or not.
  def handle_response(_), do: nil
end
