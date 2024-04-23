defmodule TransportWeb.Live.NotificationsLive do
  use Phoenix.LiveView
  import Ecto.Query
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  def mount(
        _params,
        %{"current_user" => %{"id" => user_id}, "locale" => locale, "role" => :reuser = role},
        socket
      ) do
    Gettext.put_locale(locale)

    current_contact =
      DB.Contact.base_query()
      |> preload(:followed_datasets)
      |> where([contact: c], c.datagouv_user_id == ^user_id)
      |> DB.Repo.one!()

    datasets = Map.fetch!(current_contact, :followed_datasets)
    subscriptions = notification_subscriptions_for_datasets(datasets, current_contact, :reuser)

    socket =
      assign(socket, %{
        current_contact: current_contact,
        role: role,
        datasets: datasets,
        subscriptions: subscriptions,
        all_notifications_enabled: all_notifications_enabled?(subscriptions),
        available_reasons: [
          %{
            reason: DB.NotificationSubscription.reason(:expiration),
            explanations: dgettext("reuser-space", "data expiration notification explanation")
          },
          %{
            reason: DB.NotificationSubscription.reason(:dataset_with_error),
            explanations: dgettext("reuser-space", "validation errors notification explanation")
          },
          %{
            reason: DB.NotificationSubscription.reason(:resource_unavailable),
            explanations: dgettext("reuser-space", "unavailable resources notification explanation")
          },
          %{
            reason: DB.NotificationSubscription.reason(:resources_changed),
            explanations: dgettext("reuser-space", "resources changed notification explanation")
          }
        ]
      })

    {:ok, socket}
  end

  def mount(
        _params,
        %{"current_user" => current_user, "locale" => locale, "token" => token, "role" => :producer = role},
        socket
      ) do
    Gettext.put_locale(locale)

    {socket, datasets, current_contact, subscriptions} =
      case DB.Dataset.datasets_for_user(token) do
        datasets when is_list(datasets) ->
          current_contact = DB.Repo.get_by!(DB.Contact, datagouv_user_id: current_user["id"])
          subscriptions = notification_subscriptions_for_datasets(datasets, current_contact, :producer)
          {socket |> assign(:error, nil), datasets, current_contact, subscriptions}

        {:error, _} ->
          {socket |> assign(:error, dgettext("alert", "Unable to get all your resources for the moment")), [], nil, %{}}
      end

    socket =
      assign(socket, %{
        current_contact: current_contact,
        role: role,
        datasets: datasets,
        subscriptions: subscriptions,
        all_notifications_enabled: all_notifications_enabled?(subscriptions),
        available_reasons: [
          %{
            reason: DB.NotificationSubscription.reason(:expiration),
            explanations: dgettext("espace-producteurs", "data expiration notification explanation")
          },
          %{
            reason: DB.NotificationSubscription.reason(:dataset_with_error),
            explanations: dgettext("espace-producteurs", "validation errors notification explanation")
          },
          %{
            reason: DB.NotificationSubscription.reason(:resource_unavailable),
            explanations: dgettext("espace-producteurs", "unavailable resources notification explanation")
          }
        ]
      })

    {:ok, socket}
  end

  def handle_event(
        "toggle",
        %{"dataset-id" => dataset_id, "subscription-id" => subscription_id, "reason" => reason, "action" => action},
        %Phoenix.LiveView.Socket{} = socket
      ) do
    toggle_subscription(socket, dataset_id, subscription_id, reason, action)
    subscriptions = notification_subscriptions_for_datasets(socket)
    all_notifications_enabled = all_notifications_enabled?(subscriptions)

    {:noreply, assign(socket, subscriptions: subscriptions, all_notifications_enabled: all_notifications_enabled)}
  end

  def handle_event("toggle-all", %{"action" => action}, %Phoenix.LiveView.Socket{} = socket)
      when action in ["turn_on", "turn_off"] do
    toggle_all_subscriptions(socket, action)

    subscriptions = notification_subscriptions_for_datasets(socket)
    all_notifications_enabled = all_notifications_enabled?(subscriptions)

    {:noreply, assign(socket, subscriptions: subscriptions, all_notifications_enabled: all_notifications_enabled)}
  end

  defp notification_subscriptions_for_datasets(%Phoenix.LiveView.Socket{assigns: assigns}) do
    notification_subscriptions_for_datasets(assigns.datasets, assigns.current_contact, assigns.role)
  end

  defp notification_subscriptions_for_datasets(datasets, current_contact, :reuser = role) do
    current_contact
    |> DB.Repo.preload(:notification_subscriptions, force: true)
    |> Map.fetch!(:notification_subscriptions)
    |> Enum.reject(fn %DB.NotificationSubscription{dataset_id: dataset_id, role: ns_role} ->
      is_nil(dataset_id) or ns_role != role
    end)
    |> Enum.reduce(subscriptions_empty_map(role, datasets), fn %DB.NotificationSubscription{} = subscription, acc ->
      put_in(acc, [subscription.dataset_id, subscription.reason, :user_subscription], subscription)
    end)
  end

  defp notification_subscriptions_for_datasets(datasets, current_contact, :producer = role) do
    datasets
    |> Enum.map(fn %DB.Dataset{id: id} -> id end)
    |> DB.NotificationSubscription.producer_subscriptions_for_datasets(current_contact.id)
    |> Enum.uniq_by(& &1.id)
    # keep alphabetical order while injecting with reduce
    |> Enum.reverse()
    |> Enum.reduce(subscriptions_empty_map(role, datasets), fn subscription, acc ->
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

  defp toggle_subscription(
         %Phoenix.LiveView.Socket{assigns: %{current_contact: current_contact, role: role}},
         dataset_id,
         _subscription_id,
         reason,
         "turn_on"
       ) do
    %{contact_id: current_contact.id, dataset_id: dataset_id, reason: reason, source: :user, role: role}
    |> DB.NotificationSubscription.insert!()
  end

  defp toggle_subscription(
         %Phoenix.LiveView.Socket{assigns: %{current_contact: current_contact}},
         _dataset_id,
         subscription_id,
         reason,
         "turn_off"
       ) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.id == ^subscription_id and ns.contact_id == ^current_contact.id and ns.reason == ^reason
    )
    |> DB.Repo.one!()
    |> DB.Repo.delete!()
  end

  defp toggle_all_subscriptions(
         %Phoenix.LiveView.Socket{assigns: %{subscriptions: old_subscriptions}} = socket,
         "turn_on"
       ) do
    subscriptions_to_create =
      Enum.flat_map(old_subscriptions, fn {dataset_id, reason_map} ->
        reason_map
        |> Map.filter(fn {_, v} -> match?(%{user_subscription: nil}, v) end)
        |> Map.keys()
        |> Enum.map(fn reason -> {dataset_id, reason} end)
      end)

    DB.Repo.transaction(fn ->
      Enum.each(subscriptions_to_create, fn {dataset_id, reason} ->
        toggle_subscription(socket, dataset_id, nil, reason, "turn_on")
      end)
    end)
  end

  defp toggle_all_subscriptions(
         %Phoenix.LiveView.Socket{assigns: %{current_contact: %{id: contact_id}, role: role}},
         "turn_off"
       ) do
    DB.NotificationSubscription.base_query()
    |> where(
      [notification_subscription: ns],
      ns.contact_id == ^contact_id and ns.role == ^role and not is_nil(ns.dataset_id)
    )
    |> DB.Repo.delete_all()
  end

  defp subscriptions_empty_map(role, datasets) do
    reasons =
      Map.new(DB.NotificationSubscription.reasons_related_to_datasets(role), fn reason ->
        {reason, %{user_subscription: nil, team_subscriptions: []}}
      end)

    Map.new(datasets, fn %DB.Dataset{id: dataset_id} -> {dataset_id, reasons} end)
  end

  defp all_notifications_enabled?(subscriptions) do
    Enum.all?(subscriptions, fn {_, reason_map} ->
      Enum.all?(reason_map, fn {_, %{user_subscription: user_subscription}} ->
        not is_nil(user_subscription)
      end)
    end)
  end
end
