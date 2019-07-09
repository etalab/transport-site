defmodule Datagouvfr.Client.Resources do
  @moduledoc """
  Abstraction of data.gouv.fr resource
  """
  alias Datagouvfr.Client

  def upload(conn, dataset_id, id, file) do
    Client.post(
      conn,
      Path.join(["datasets", dataset_id, "resources", id, "upload"]),
      {"file", file},
       [{"content-type", "multipart/form-data"}]
    )
  end
end
