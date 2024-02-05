defmodule TransportWeb.NotificationController do
  @moduledoc """
  Display notification subscriptions, create and delete subscriptions from the producer space.
  """
  use TransportWeb, :controller
  import Ecto.Query

  def index(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_user_id}}} = conn, _) do
    {conn, datasets} =
      case DB.Dataset.datasets_for_user(conn) do
        datasets when is_list(datasets) ->
          {conn, datasets}

        {:error, _} ->
          conn = conn |> put_flash(:error, dgettext("alert", "Unable to get all your resources for the moment"))
          {conn, []}
      end

    current_contact = DB.Repo.get_by(DB.Contact, datagouv_user_id: datagouv_user_id)

    conn
    |> assign(:datasets, datasets)
    |> assign(:current_contact, current_contact)
    |> assign(:notification_subscriptions, notification_subscriptions_for_datasets(datasets, current_contact))
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

  defp notification_subscriptions_for_datasets(datasets, current_contact) do
    dataset_ids = datasets |> Enum.map(& &1.id)

    subscriptions_list = load_subscriptions_for_datasets_and_contact(dataset_ids, current_contact)

    subscriptions_list
    |> Enum.sort_by(&{&1.dataset.custom_title, &1.reason})
    |> Enum.group_by(& &1.dataset)
    |> Map.new(fn {dataset, subscriptions} -> {dataset, group_by_reason_and_contact(subscriptions, current_contact)} end)
  end

  defp load_subscriptions_for_datasets_and_contact(dataset_ids, current_contact) do
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> preload(:contact)
    |> preload(:dataset)
    |> where(
      [notification_subscription: ns, contact: c],
      ns.dataset_id in ^dataset_ids and not is_nil(ns.dataset_id) and
        ns.role == :producer and
        c.organization == ^current_contact.organization
    )
    |> DB.Repo.all()
  end

  defp group_by_reason_and_contact(subscriptions, current_contact) do
    subscriptions
    |> Enum.group_by(& &1.reason)
    |> Map.new(fn {reason, subscriptions} -> {reason, subgroup_by_contact(subscriptions, current_contact)} end)
  end

  defp subgroup_by_contact(subscriptions, current_contact) do
    {user_subscriptions, team_subscriptions} = Enum.split_with(subscriptions, & &1.contact == current_contact)
    user_subscription =
      case user_subscriptions do
      [] -> nil
      [subscription] -> subscription
    end
    %{user_subscription: user_subscription, team_subscriptions: team_subscriptions}

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

  @spec contact_for_user(Plug.Conn.t()) :: DB.Contact.t()
  defp contact_for_user(%Plug.Conn{assigns: %{current_user: %{"id" => user_id}}}) do
    DB.Repo.get_by!(DB.Contact, datagouv_user_id: user_id)
  end

  defp existing_reasons(%Ecto.Query{} = query) do
    query
    |> select([notification_subscription: ns], ns.reason)
    |> DB.Repo.all()
    |> Enum.map(&to_string/1)
  end
end
