defmodule Datagouvfr.Client.Resources do
  @moduledoc """
  Abstraction of data.gouv.fr resource
  """
  alias Datagouvfr.Client.OAuth, as: Client

  @spec update(Plug.Conn.t(), binary, binary, map) :: Client.oauth2_response
  def update(conn, dataset_id, id, %{"resource_file" => file}) do
    Client.post(
      conn,
      Path.join(["datasets", dataset_id, "resources", id, "upload"]),
      {"file", file},
       [{"content-type", "multipart/form-data"}]
    )
  end

  def update(conn, dataset_id, id, %{"url" => url}) do
    Client.put(
      conn,
      Path.join(["datasets", dataset_id, "resources", id]),
      %{
        "url" => url,
        "filetype" => "remote"
      }
    )
  end
end
