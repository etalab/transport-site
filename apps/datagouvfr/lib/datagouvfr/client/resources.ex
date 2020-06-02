defmodule Datagouvfr.Client.Resources do
  @moduledoc """
  Abstraction of data.gouv.fr resource
  """
  alias Datagouvfr.Client.API
  alias Datagouvfr.Client.OAuth, as: Client

  @format_to_mime %{
    "GTFS" => "application/zip",
    "netex" => "application/zip"
  }
  @fields ["url", "format", "title", "filetype"]

  @spec update(Plug.Conn.t(), map) :: Client.oauth2_response() | nil
  def update(conn, %{"resource_file" => _file} = params) do
    case upload_query(conn, params) do
      {:ok, %{"id" => r_id}} = upload_resp ->
        new_params =
          params
          |> Map.drop(["resource_file"])
          |> Map.put("resource_id", r_id)
          |> Map.put("filetype", "file")

        update(conn, new_params, upload_resp)

      error ->
        error
    end
  end

  @spec update(Plug.Conn.t(), map, Client.oauth2_response() | nil) :: Client.oauth2_response() | nil
  def update(conn, params, prev_resp \\ nil) do
    params
    |> Map.take(@fields)
    |> Enum.filter(fn {_k, v} -> v != "" end)
    |> Map.new()
    |> case do
      params when map_size(params) == 0 ->
        # We have nothing to upload, so we return the previous response
        prev_resp

      filtered_params ->
        payload =
          params
          |> get()
          |> Map.merge(filtered_params)
          |> Map.put_new("filetype", "remote")
          |> put_mime(params)

        Client.put(conn, make_path(params), payload)
    end
  end

  @spec get(map) :: map
  def get(%{"resource_id" => _id} = params) do
    params
    |> make_path()
    |> API.get()
    |> case do
      {:ok, resource} -> resource |> Map.take(@fields)
      _ -> %{}
    end
  end

  def get(_), do: %{}

  @spec put_mime(map(), map()) :: map()
  defp put_mime(payload, params) do
    if Map.has_key?(@format_to_mime, params["format"]) do
      Map.put(payload, "mime", @format_to_mime[params["format"]])
    else
      payload
    end
  end

  @spec upload_query(Plug.Conn.t(), map()) :: Client.oauth2_response()
  defp upload_query(conn, params),
    do:
      Client.post(
        conn,
        make_path(params, ["upload"]),
        {:file, params["resource_file"]},
        [{"content-type", "multipart/form-data"}]
      )

  @spec make_path(map(), [binary()]) :: binary()
  defp make_path(params, suffix \\ [])

  defp make_path(%{"dataset_id" => d_id, "resource_id" => r_id}, suffix),
    do: Path.join(["datasets", d_id, "resources", r_id] ++ suffix)

  defp make_path(%{"dataset_id" => d_id}, suffix), do: Path.join(["datasets", d_id] ++ suffix)
end
