defmodule TransportWeb.Backoffice.NotificationSubscriptionController do
  use TransportWeb, :controller
  import Ecto.Query
  @target_html_anchor "#notification_subscriptions"

  @doc """
  Creates a notification subscription:
  - for reasons related to a specific dataset
  - OR for reasons that are not related to datasets.
  """
  def create(
        %Plug.Conn{} = conn,
        %{"contact_id" => contact_id, "dataset_id" => dataset_id, "redirect_location" => _} = params
      ) do
    existing_reasons = reasons_for_contact_and_dataset(params)

    params
    |> picked_reasons()
    |> Enum.reject(&(&1 in existing_reasons))
    |> Enum.each(fn reason ->
      %{contact_id: contact_id, dataset_id: dataset_id, reason: reason, source: :admin, role: :producer}
      |> DB.NotificationSubscription.insert!()
    end)

    conn
    |> put_flash(:info, "L'abonnement a été créé")
    |> redirect(to: redirect_location(conn, params))
  end

  def create(%Plug.Conn{} = conn, %{"contact_id" => contact_id, "redirect_location" => "contact"} = params) do
    possible_reasons = Transport.NotificationReason.subscribable_platform_wide_reasons(:producer)
    picked_reasons = params |> picked_reasons()

    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.reason not in ^picked_reasons and ns.contact_id == ^contact_id and ns.reason in ^possible_reasons
    )
    |> DB.Repo.delete_all()

    existing_reasons = platform_wide_reasons_for_contact(params)

    picked_reasons
    |> Enum.reject(&(&1 in existing_reasons))
    |> Enum.each(fn reason ->
      %{contact_id: contact_id, reason: reason, dataset_id: nil, source: :admin, role: :producer}
      |> DB.NotificationSubscription.insert!()
    end)

    conn
    |> put_flash(:info, "Abonnements mis à jour")
    |> redirect(to: redirect_location(conn, params))
  end

  def delete(%Plug.Conn{} = conn, %{"id" => id, "redirect_location" => _} = params) do
    notification_subscription = DB.NotificationSubscription |> DB.Repo.get!(id) |> DB.Repo.delete!()

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
    possible_reasons = Transport.NotificationReason.all_reasons() |> Enum.map(&to_string/1)

    params |> Map.filter(fn {k, v} -> k in possible_reasons and v == "true" end) |> Map.keys()
  end

  defp reasons_for_contact_and_dataset(%{"contact_id" => contact_id, "dataset_id" => dataset_id}) do
    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], ns.dataset_id == ^dataset_id and ns.contact_id == ^contact_id)
    |> existing_reasons()
  end

  defp platform_wide_reasons_for_contact(%{"contact_id" => contact_id}) do
    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], is_nil(ns.dataset_id) and ns.contact_id == ^contact_id)
    |> existing_reasons()
  end

  defp existing_reasons(%Ecto.Query{} = query) do
    query
    |> select([notification_subscription: ns], ns.reason)
    |> DB.Repo.all()
    |> Enum.map(&to_string/1)
  end

  defp redirect_location(
         %Plug.Conn{} = conn,
         %{"redirect_location" => redirect_location} = params,
         %DB.NotificationSubscription{} = notification_subscription
       ) do
    key = redirect_location <> "_id"
    redirect_location(conn, Map.put(params, key, Map.fetch!(notification_subscription, String.to_existing_atom(key))))
  end

  defp redirect_location(%Plug.Conn{} = conn, %{"redirect_location" => "contact", "contact_id" => contact_id}) do
    backoffice_contact_path(conn, :edit, contact_id) <> @target_html_anchor
  end

  defp redirect_location(%Plug.Conn{} = conn, %{"redirect_location" => "dataset", "dataset_id" => dataset_id}) do
    backoffice_page_path(conn, :edit, dataset_id) <> @target_html_anchor
  end
end
