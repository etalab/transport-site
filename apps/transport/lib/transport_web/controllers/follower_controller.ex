defmodule TransportWeb.FollowerController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Datasets

  def toggle(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    current_user_subscribed = Datasets.current_user_subscribed?(conn, dataset_id)
    conn
    |> toggle_subscription(dataset_id, current_user_subscribed)
    |> case do
      {:error, error} ->
        conn
        |> put_flash(:error, error)
      {:ok, _} -> conn
    end
    |> redirect(to: dataset_path(conn, :details, dataset_id))
  end

  defp toggle_subscription(conn, dataset_id, false), do:
    Datasets.post_followers(conn, dataset_id)
  defp toggle_subscription(conn, dataset_id, true), do:
    Datasets.delete_followers(conn, dataset_id)
end
