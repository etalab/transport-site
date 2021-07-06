defmodule Datagouvfr.Client do
  @moduledoc """
  An API client for data.gouv.fr
  """

  defmacro __using__([]) do
    quote do
      require Logger

      @type path :: list(binary()) | binary

      @spec base_url :: binary
      def base_url, do: :transport |> Application.fetch_env!(:datagouvfr_site) |> Path.join("/api/1/")

      @spec process_url(path) :: String.t()
      def process_url(path) when is_list(path), do: path |> Path.join() |> process_url()

      def process_url(path) when is_binary(path) do
        base_url()
        |> Path.join(path)
        |> URI.parse()
        |> add_trailing_slash
      end

      @spec post_process({:error, any} | {:ok, %{body: any, status_code: any}}) ::
              {:error, any} | {:ok, any}
      def post_process(response) do
        Logger.debug(fn -> "response: #{inspect(response)}" end)

        case response do
          {:ok, %{status_code: status_code, body: body}} when status_code in [200, 201, 202, 204] -> {:ok, body}
          {:ok, %{status_code: _, body: body}} -> {:error, body}
          {:error, error} -> {:error, error}
        end
      end

      # private

      @spec add_trailing_slash(map() | path) :: binary()
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

      @spec default_content_type([{binary(), binary()}]) :: [{binary(), binary()}]
      defp default_content_type(headers) do
        case Enum.any?(headers, &content_type?(&1)) do
          true -> headers
          false -> [{"content-type", "application/json"} | headers]
        end
      end

      @spec content_type?({binary(), binary()}) :: boolean
      defp content_type?(header) do
        header
        |> elem(0)
        |> String.downcase()
        |> Kernel.==("content-type")
      end
    end
  end
end
