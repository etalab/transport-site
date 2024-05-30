defmodule TransportWeb.ReuserSpaceController do
  use TransportWeb, :controller
  import Ecto.Query

  plug(:find_dataset_or_redirect when action in [:datasets_edit, :unfavorite])

  def espace_reutilisateur(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}} = conn, _) do
    contact = DB.Repo.get_by!(DB.Contact, datagouv_user_id: datagouv_user_id)
    followed_datasets_ids = contact |> Ecto.assoc(:followed_datasets) |> select([d], d.id) |> DB.Repo.all()

    conn
    |> assign(:contact, contact)
    |> assign(:followed_datasets_ids, followed_datasets_ids)
    |> render("index.html")
  end

  def datasets_edit(%Plug.Conn{} = conn, _), do: render(conn, "datasets_edit.html")

  def unfavorite(%Plug.Conn{assigns: %{dataset: %DB.Dataset{} = dataset, contact: %DB.Contact{} = contact}} = conn, _) do
    DB.DatasetFollower.unfollow!(contact, dataset)
    delete_notification_subscriptions(contact, dataset)

    conn
    |> put_flash(
      :info,
      dgettext("reuser-space", "%{dataset_title} has been removed from your favorites",
        dataset_title: dataset.custom_title
      )
    )
    |> redirect(to: reuser_space_path(conn, :espace_reutilisateur))
  end

  defp delete_notification_subscriptions(%DB.Contact{id: contact_id}, %DB.Dataset{id: dataset_id}) do
    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], ns.contact_id == ^contact_id and ns.dataset_id == ^dataset_id)
    |> DB.Repo.delete_all()
  end

  defp find_dataset_or_redirect(
         %Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}, path_params: %{"dataset_id" => dataset_id}} =
           conn,
         _options
       ) do
    DB.Contact.base_query()
    |> join(:inner, [contact: c], d in assoc(c, :followed_datasets), as: :dataset)
    |> where([contact: c], c.datagouv_user_id == ^datagouv_user_id)
    |> where([dataset: d], d.id == ^dataset_id)
    |> select([contact: c, dataset: d], %{contact: c, dataset: d})
    |> DB.Repo.all()
    |> case do
      [%{contact: %DB.Contact{}, dataset: %DB.Dataset{}} = results] ->
        conn |> merge_assigns(results)

      _ ->
        conn
        |> put_flash(:error, dgettext("alert", "Unable to get this dataset for the moment"))
        |> redirect(to: reuser_space_path(conn, :espace_reutilisateur))
        |> halt()
    end
  end
end
