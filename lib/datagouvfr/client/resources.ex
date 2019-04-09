defmodule Datagouvfr.Client.Resources do
  @moduledoc """
  Abstraction of data.gouv.fr resource
  """
  import Datagouvfr.Client, only: [post_request: 4]

  def upload(conn, dataset_id, id, file) do
    post_request(
      conn,
      Path.join(["datasets", dataset_id, "resources", id, "upload"]),
      {"file", file},
       [{"content-type", "multipart/form-data"}]
    )
  end
end
