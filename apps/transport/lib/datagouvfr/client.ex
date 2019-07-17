defmodule Datagouvfr.Client do
  @moduledoc """
  An API client for data.gouv.fr
  """

  defmacro __using__([]) do
    quote do
      @type path :: list(binary()) | binary

      @spec base_url :: binary
      def base_url, do: :transport |> Application.get_env(:datagouvfr_site) |> Path.join("/api/1/")

      @spec process_url(path) :: String.t
      def process_url(path) when is_list(path), do: path |> Path.join() |> process_url()
      def process_url(path) when is_binary(path) do
        base_url()
        |> Path.join(path)
        |> URI.parse
        |> add_trailing_slash
      end

      @spec post_process({:error, any} | {:ok, %{body: any, status_code: any}}) ::
              {:error, any} | {:ok, any}
      def post_process(response) do
        case response do
          {:ok, %{status_code: 200, body: body}} -> {:ok, body}
          {:ok, %{status_code: 201, body: body}} -> {:ok, body}
          {:ok, %{status_code: _, body: body}} -> {:error, body}
          {:error, error} -> {:error, error}
        end
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
  end
end
