defmodule TransportWeb.EspaceProducteur.NotificationLive do
  use Phoenix.LiveView
  import Ecto.Query
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  def mount(_params, %{"current_user" => current_user, "locale" => locale, "token" => token}, socket) do
    Gettext.put_locale(locale)

    {socket, datasets, current_contact, subscriptions} =
      case DB.Dataset.datasets_for_user(token) do
        datasets when is_list(datasets) ->
          current_contact = DB.Repo.get_by!(DB.Contact, datagouv_user_id: current_user["id"])
          subscriptions = notification_subscriptions_for_datasets(datasets, current_contact)
          {socket |> assign(:error, nil), datasets, current_contact, subscriptions}

        {:error, _} ->
          {socket |> assign(:error, dgettext("alert", "Unable to get all your resources for the moment")), [], nil, %{}}
      end

    socket =
      socket
      |> assign(:current_contact, current_contact)
      |> assign(:locale, locale)
      |> assign(:datasets, datasets)
      |> assign(:subscriptions, subscriptions)
      |> assign(:all_notifications_enabled, all_notifications_enabled?(subscriptions))

    {:ok, socket}
  end

  def handle_event(
        "toggle",
        %{"dataset-id" => dataset_id, "subscription-id" => subscription_id, "reason" => reason, "action" => action},
        %Phoenix.LiveView.Socket{assigns: %{current_contact: current_contact, datasets: datasets}} = socket
      ) do
    toggle_subscription(current_contact, dataset_id, subscription_id, reason, action)
    subscriptions = notification_subscriptions_for_datasets(datasets, current_contact)
    all_notifications_enabled = all_notifications_enabled?(subscriptions)

    {:noreply, assign(socket, subscriptions: subscriptions, all_notifications_enabled: all_notifications_enabled)}
  end

  def handle_event(
        "toggle-all",
        %{"action" => action},
        %Phoenix.LiveView.Socket{
          assigns: %{current_contact: current_contact, datasets: datasets, subscriptions: old_subscriptions}
        } = socket
      )
      when action in ["turn_on", "turn_off"] do
    toggle_all_subscriptions(current_contact, old_subscriptions, action)

    subscriptions = notification_subscriptions_for_datasets(datasets, current_contact)

    all_notifications_enabled = all_notifications_enabled?(subscriptions)
    {:noreply, assign(socket, subscriptions: subscriptions, all_notifications_enabled: all_notifications_enabled)}
  end

  defp notification_subscriptions_for_datasets(datasets, current_contact) do
    dataset_ids = Enum.map(datasets, & &1.id)

    dataset_ids
    |> DB.NotificationSubscription.producer_subscriptions_for_datasets(current_contact.id)
    |> Enum.uniq_by(& &1.id)
    # keep alphabetical order while injecting with reduce
    |> Enum.reverse()
    |> Enum.reduce(subscription_empty_map(dataset_ids), fn subscription, acc ->
      if subscription.contact == current_contact do
        acc |> put_in([subscription.dataset_id, subscription.reason, :user_subscription], subscription)
      else
        acc
        |> put_in(
          [subscription.dataset_id, subscription.reason, :team_subscriptions],
          [subscription | acc[subscription.dataset_id][subscription.reason][:team_subscriptions]]
        )
      end
    end)
  end

  defp toggle_subscription(current_contact, dataset_id, _subscription_id, reason, "turn_on") do
    %{contact_id: current_contact.id, dataset_id: dataset_id, reason: reason, source: :user, role: :producer}
    |> DB.NotificationSubscription.insert!()
  end

  defp toggle_subscription(current_contact, _dataset_id, subscription_id, reason, "turn_off") do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.id == ^subscription_id and ns.contact_id == ^current_contact.id and ns.reason == ^reason
    )
    |> DB.Repo.one!()
    |> DB.Repo.delete!()
  end

  defp toggle_all_subscriptions(current_contact, old_subscriptions, "turn_on") do
    Enum.each(old_subscriptions, fn {dataset_id, reason_map} ->
      reason_map
      |> Map.filter(fn {_, v} -> match?(%{user_subscription: nil}, v) end)
      |> Map.keys()
      |> Enum.each(fn reason ->
        toggle_subscription(current_contact, dataset_id, nil, reason, "turn_on")
      end)
    end)
  end

  defp toggle_all_subscriptions(current_contact, _old_subscriptions, "turn_off") do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.contact_id == ^current_contact.id and ns.role == :producer and not is_nil(ns.dataset_id)
    )
    |> DB.Repo.delete_all()
  end

  defp subscription_empty_map(dataset_ids) do
    Map.new(dataset_ids, fn dataset_id ->
      reasons_map =
        DB.NotificationSubscription.reasons_related_to_datasets()
        |> Map.new(fn reason -> {reason, %{user_subscription: nil, team_subscriptions: []}} end)

      {dataset_id, reasons_map}
    end)
  end

  defp all_notifications_enabled?(subscriptions) do
    Enum.all?(subscriptions, fn {_, reason_map} ->
      Enum.all?(reason_map, fn {_, %{user_subscription: user_subscription, team_subscriptions: _}} ->
        not is_nil(user_subscription)
      end)
    end)
  end
end
