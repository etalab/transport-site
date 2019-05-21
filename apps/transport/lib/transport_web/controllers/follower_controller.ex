defmodule TransportWeb.FollowerController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Datasets

  def subscribe_or_unsubscribe(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id, "is_subscribed" => "false"}) do
    conn
    |> Datasets.post_followers(dataset_id)
    |> handle_followers(conn, dataset_id)
  end

  def subscribe_or_unsubscribe(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id, "is_subscribed" => "true"}) do
    conn
    |> Datasets.delete_followers(dataset_id)
    |> handle_followers(conn, dataset_id)
  end

  defp handle_followers(datagouv_response, conn, dataset_id) do
    datagouv_response
    |> case do
      {:error, error} ->
        conn
        |> put_flash(:error, error)
      {:ok, _} -> conn
    end
    |> redirect(to: dataset_path(conn, :details, dataset_id))
  end
end
