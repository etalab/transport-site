defmodule TransportWeb.FollowerController do
  use TransportWeb, :controller
  alias Datagouvfr.Client.Datasets

  def toggle(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    current_user_subscribed = Datasets.current_user_subscribed?(conn, dataset_id)

    method =
      if current_user_subscribed do
        :delete_followers
      else
        :post_followers
      end

    Datasets
    # credo:disable-for-next-line
    |> apply(method, [conn, dataset_id])
    |> case do
      {:error, error} ->
        conn
        |> put_flash(:error, error)

      {:ok, _} ->
        conn
    end
    |> redirect(to: dataset_path(conn, :details, dataset_id))
  end
end
