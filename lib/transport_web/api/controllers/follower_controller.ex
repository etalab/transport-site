defmodule TransportWeb.API.FollowerController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client.Datasets

  def create(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    conn
    |> Datasets.post_followers(dataset_id)
    |> case do
      {:ok, body} -> render(conn, data: body)
      {:error, error} -> render(conn, errors: [error])
    end
  end

  def delete(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    conn
    |> Datasets.delete_followers(dataset_id)
    |> case do
      {:ok, body} -> render(conn, data: body)
      {:error, error} -> render(conn, errors: [error])
    end
  end
end
