defmodule Datagouvfr.Client.Resources do
  @moduledoc """
  Abstraction of data.gouv.fr resource
  """
  alias Datagouvfr.Client.API
  alias Datagouvfr.Client.OAuth, as: Client

  @format_to_mime %{
    "GTFS" => "application/zip",
    "NeTEx" => "application/zip"
  }
  @fields ["url", "format", "title", "filetype"]

  # when the resource has an uploaded file
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
  defp upload_query(conn, %{"resource_file" => %{path: file_path, filename: file_name}} = params) do
    Client.post(
      conn,
      make_path(params, ["upload"]),
      # found here how to properly upload the file: https://github.com/edgurgel/httpoison/issues/237
      # (the underlying lib is the same: hackney)
      {:multipart,
       [
         {:file, file_path, {"form-data", [{:name, "file"}, {:filename, file_name}]}, []}
       ]},
      [{"content-type", "multipart/form-data"}]
    )
  end

  defp upload_query(conn, _), do: {:error, "no file to upload"}

  @spec make_path(map(), [binary()]) :: binary()
  # The different data.gouv.fr api calls targeted by this function :
  # * POST on /datasets/{dataset}/resources/ => creates a new resource for the given dataset if the resource source is a remote file
  # * POST on /datasets/{dataset}/upload/ => creates a new resource for the given dataset if the resource is an uploaded file
  # * PUT on /datasets/{dataset}/resources/{rid}/ => updates the information about the given resource
  # * POST on /datasets/{dataset}/resources/{rid}/upload/ => upload a new file for the given existing resource

  # See https://doc.data.gouv.fr/api/reference/#/datasets for reference

  defp make_path(params, suffix \\ [])

  defp make_path(%{"dataset_id" => d_id, "resource_id" => r_id}, suffix),
    do: Path.join(["datasets", d_id, "resources", r_id] ++ suffix)

  defp make_path(%{"dataset_id" => d_id}, suffix), do: Path.join(["datasets", d_id] ++ suffix)
end
