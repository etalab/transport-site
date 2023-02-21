defmodule TransportWeb.Backoffice.NotificationSubscriptionController do
  use TransportWeb, :controller
  import Ecto.Query
  @target_html_anchor "#notification_subscriptions"

  def create(
        %Plug.Conn{} = conn,
        %{"contact_id" => contact_id, "dataset_id" => dataset_id, "redirect_location" => _} = params
      ) do
    existing_reasons =
      DB.NotificationSubscription.base_query()
      |> where([notification_subscription: ns], ns.dataset_id == ^dataset_id and ns.contact_id == ^contact_id)
      |> select([notification_subscription: ns], ns.reason)
      |> DB.Repo.all()
      |> Enum.map(&to_string/1)

    params
    |> picked_reasons()
    |> Enum.reject(&(&1 in existing_reasons))
    |> Enum.each(fn reason ->
      %{contact_id: contact_id, dataset_id: dataset_id, reason: reason, source: :admin}
      |> DB.NotificationSubscription.insert!()
    end)

    conn
    |> put_flash(:info, "L'abonnement a été créé")
    |> redirect(to: redirect_location(conn, params))
  end

  def delete(%Plug.Conn{} = conn, %{"id" => id, "redirect_location" => _} = params) do
    notification_subscription = DB.Repo.get!(DB.NotificationSubscription, id)
    notification_subscription |> DB.Repo.delete!()

    conn
    |> put_flash(:info, "L'abonnement a été supprimé")
    |> redirect(to: redirect_location(conn, params, notification_subscription))
  end

  def delete_for_contact_and_dataset(
        %Plug.Conn{} = conn,
        %{"contact_id" => contact_id, "dataset_id" => dataset_id, "redirect_location" => _} = params
      ) do
    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], ns.dataset_id == ^dataset_id and ns.contact_id == ^contact_id)
    |> DB.Repo.delete_all()

    conn
    |> put_flash(:info, "Les abonnements ont été supprimés")
    |> redirect(to: redirect_location(conn, params))
  end

  defp picked_reasons(%{} = params) do
    possible_reasons = DB.NotificationSubscription.reasons_related_to_datasets() |> Enum.map(&to_string/1)

    params |> Map.filter(fn {k, v} -> k in possible_reasons and v == "true" end) |> Map.keys()
  end

  defp redirect_location(
         %Plug.Conn{} = conn,
         %{"redirect_location" => redirect_location},
         %DB.NotificationSubscription{} = notification_subscription
       ) do
    case redirect_location do
      "contact" -> backoffice_contact_path(conn, :edit, notification_subscription.contact_id)
      "dataset" -> backoffice_page_path(conn, :edit, notification_subscription.dataset_id)
    end <> @target_html_anchor
  end

  defp redirect_location(%Plug.Conn{} = conn, %{
         "contact_id" => contact_id,
         "dataset_id" => dataset_id,
         "redirect_location" => redirect_location
       }) do
    case redirect_location do
      "contact" -> backoffice_contact_path(conn, :edit, contact_id)
      "dataset" -> backoffice_page_path(conn, :edit, dataset_id)
    end <> @target_html_anchor
  end
end
