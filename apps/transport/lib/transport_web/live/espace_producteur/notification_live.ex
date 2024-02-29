defmodule TransportWeb.EspaceProducteur.NotificationLive do
  use Phoenix.LiveView
  import Ecto.Query
  use TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  def mount(
        _params,
        %{
          "current_user" => current_user,
          "locale" => locale
        },
        socket
      ) do
    {socket, datasets} =
      case DB.Dataset.datasets_for_user(current_user) do
        datasets when is_list(datasets) ->
          {socket, datasets}

        {:error, _} ->
          # TODO : dunno what to do here for a liveview. Render an error page?
          {socket |> put_flash(:error, dgettext("alert", "Unable to get all your resources for the moment")), []}
      end

    Gettext.put_locale(locale)

    current_contact = DB.Repo.get_by(DB.Contact, datagouv_user_id: current_user["id"])

    subscriptions = notification_subscriptions_for_datasets(datasets, current_contact)

    socket =
      socket
      |> assign(:current_contact, current_contact)
      |> assign(:locale, locale)
      |> assign(:datasets, datasets)
      |> assign(:subscriptions, subscriptions)

    {:ok, socket}
  end

  def handle_event(
        "toggle",
        %{"dataset-id" => dataset_id, "subscription-id" => subscription_id, "reason" => reason, "action" => action},
        socket
      ) do
    current_contact = socket.assigns.current_contact
    datasets = socket.assigns.datasets

    toggle_subscription(current_contact, dataset_id, subscription_id, reason, action)
    subscriptions = notification_subscriptions_for_datasets(datasets, current_contact)

    # TODO : alerts for success/failure
    {:noreply, assign(socket, :subscriptions, subscriptions)}
  end

  defp notification_subscriptions_for_datasets(datasets, current_contact) do
    # TODO : perhaps move to notification_subscription.ex

    dataset_ids = datasets |> Enum.map(& &1.id)

    # TODO What I want : a list of lines contact <> dataset, through the contact_organisation table
    # Something like (from "contacts_organizations", select: [:contact_id, :organization_id], where: "organization_id" in ^organization_ids) |> DB.Repo.all()

    subscriptions_list = load_subscriptions_for_datasets(dataset_ids)

    subscriptions_list
    |> Enum.group_by(& &1.dataset_id)
    |> Map.new(fn {dataset_id, subscriptions} ->
      {dataset_id, group_by_reason_and_contact(subscriptions, current_contact)}
    end)
  end

  defp load_subscriptions_for_datasets(dataset_ids) do
    # TODO Note Antoine : plutôt aller chercher les notifications à partir des datasets > même org.
    # Faudrait faire un join avec les contacts et les organisations
    # pour avoir les contacts qui sont dans la même org que le dataset
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> preload(:contact)
    |> where(
      [notification_subscription: ns, contact: c],
      ns.dataset_id in ^dataset_ids and not is_nil(ns.dataset_id) and
        ns.role == :producer
    )
    |> DB.Repo.all()
  end

  defp group_by_reason_and_contact(subscriptions, current_contact) do
    subscriptions
    |> Enum.group_by(& &1.reason)
    |> Map.new(fn {reason, subscriptions} -> {reason, subgroup_by_contact(subscriptions, current_contact)} end)
  end

  defp subgroup_by_contact(subscriptions, current_contact) do
    {user_subscriptions, team_subscriptions} = Enum.split_with(subscriptions, &(&1.contact == current_contact))

    user_subscription =
      case user_subscriptions do
        [] -> nil
        [subscription] -> subscription
      end

    %{user_subscription: user_subscription, team_subscriptions: team_subscriptions}
  end

  defp toggle_subscription(current_contact, dataset_id, _subscription_id, reason, "turn_on") do
    %{contact_id: current_contact.id, dataset_id: dataset_id, reason: reason, source: :user, role: :producer}
    |> DB.NotificationSubscription.insert!()

    # %DB.NotificationSubscription{
    #  contact_id: current_contact.id, dataset_id: dataset_id, reason: reason, source: :user, role: :producer}
    # |> DB.NotificationSubscription.changeset()
    # |> DB.Repo.insert() # It may fail if the subscription already exists, could happen if the user double-clicks
    # TODO: alert for creation?
  end

  defp toggle_subscription(current_contact, _dataset_id, subscription_id, reason, "turn_off") do
    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], ns.id == ^subscription_id and ns.contact_id == ^current_contact.id and ns.reason == ^reason)
    |> DB.Repo.one!()
    |> DB.Repo.delete!()
  end
end
