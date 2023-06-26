defmodule TransportWeb.NotificationController do
  @moduledoc """
  Display notification subscriptions, create and delete subscriptions from the producer space.
  """
  use TransportWeb, :controller
  import Ecto.Query

  def index(%Plug.Conn{assigns: %{current_user: current_user}} = conn, _) do
    {conn, datasets} =
      case DB.Dataset.datasets_for_user(conn) do
        datasets when is_list(datasets) ->
          {conn, datasets}

        {:error, _} ->
          conn = conn |> put_flash(:error, dgettext("alert", "Unable to get all your resources for the moment"))
          {conn, []}
      end

    conn
    |> assign(:datasets, datasets)
    |> assign(:notification_subscriptions, notification_subscriptions_for_user(current_user))
    |> render("index.html")
  end

  def create(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id} = params) do
    existing_reasons = reasons_for_user_and_dataset(conn, dataset_id)
    %DB.Contact{id: contact_id} = contact_for_user(conn)

    params
    |> picked_reasons()
    |> Enum.reject(&(&1 in existing_reasons))
    |> Enum.each(fn reason ->
      %{contact_id: contact_id, dataset_id: dataset_id, reason: reason, source: :user, role: :producer}
      |> DB.NotificationSubscription.insert!()
    end)

    conn
    |> put_flash(:info, dgettext("espace-producteurs", "The notification has been created"))
    |> redirect(to: notification_path(conn, :index))
  end

  defp notification_subscriptions_for_user(%{"id" => datagouv_user_id}) do
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> preload(:dataset)
    |> where(
      [notification_subscription: ns, contact: c],
      c.datagouv_user_id == ^datagouv_user_id and not is_nil(ns.dataset_id)
    )
    |> DB.Repo.all()
    |> Enum.sort_by(&{&1.dataset.custom_title, &1.reason})
    |> Enum.group_by(& &1.dataset)
  end

  def delete_for_dataset(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}} = conn, %{
        "dataset_id" => dataset_id
      }) do
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> where(
      [notification_subscription: ns, contact: c],
      ns.dataset_id == ^dataset_id and c.datagouv_user_id == ^datagouv_user_id
    )
    |> DB.Repo.delete_all()

    conn
    |> put_flash(:info, dgettext("espace-producteurs", "The notifications have been deleted"))
    |> redirect(to: notification_path(conn, :index))
  end

  def delete(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}} = conn, %{"id" => id}) do
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> where([notification_subscription: ns, contact: c], ns.id == ^id and c.datagouv_user_id == ^datagouv_user_id)
    |> DB.Repo.one!()
    |> DB.Repo.delete!()

    conn
    |> put_flash(:info, dgettext("espace-producteurs", "The notification has been deleted"))
    |> redirect(to: notification_path(conn, :index))
  end

  defp picked_reasons(%{} = params) do
    possible_reasons = DB.NotificationSubscription.reasons_related_to_datasets() |> Enum.map(&to_string/1)

    params |> Map.filter(fn {k, v} -> k in possible_reasons and v == "true" end) |> Map.keys()
  end

  defp reasons_for_user_and_dataset(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}}, dataset_id) do
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> where(
      [notification_subscription: ns, contact: c],
      ns.dataset_id == ^dataset_id and c.datagouv_user_id == ^datagouv_user_id
    )
    |> existing_reasons()
  end

  defp contact_for_user(%Plug.Conn{assigns: %{current_user: current_user}}) do
    TransportWeb.SessionController.find_or_create_contact(current_user)
  end

  defp existing_reasons(%Ecto.Query{} = query) do
    query
    |> select([notification_subscription: ns], ns.reason)
    |> DB.Repo.all()
    |> Enum.map(&to_string/1)
  end
end
