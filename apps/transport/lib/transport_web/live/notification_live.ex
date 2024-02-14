defmodule TransportWeb.NotificationLive do
  use Phoenix.LiveView
  import Ecto.Query
  use TransportWeb.InputHelpers
  import TransportWeb.InputHelpers
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
    datasets =
      case DB.Dataset.datasets_for_user(current_user) do
        datasets when is_list(datasets) ->
          datasets

        {:error, _} ->
          # TODO : dunno what to do here for a liveview. Render an error page?
          []
      end

    # I don’t know what I’m doing here
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
    toggle_subscription(current_contact, dataset_id, subscription_id, reason, action)

    # {:noreply, assign(socket, :subscriptions, fetch_subscriptions())} TODO
    {:noreply, socket}
  end

  defp notification_subscriptions_for_datasets(datasets, current_contact) do
    # TODO : perhaps move to notification_subscription.ex

    dataset_ids = datasets |> Enum.map(& &1.id)

    subscriptions_list = load_subscriptions_for_datasets_and_contact(dataset_ids, current_contact)

    subscriptions_list
    |> Enum.sort_by(&{&1.dataset.custom_title, &1.reason})
    |> Enum.group_by(& &1.dataset.id)
    |> Map.new(fn {dataset, subscriptions} -> {dataset, group_by_reason_and_contact(subscriptions, current_contact)} end)
  end

  defp load_subscriptions_for_datasets_and_contact(dataset_ids, current_contact) do
    # TODO Note Antoine : plutôt aller chercher les notifications à partir des datasets > même org.
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> preload(:contact)
    |> preload(:dataset)
    |> where(
      [notification_subscription: ns, contact: c],
      # That’s not so good, it’s just a string
      # TODO NOPE, it’s a display name, can be overriden
      ns.dataset_id in ^dataset_ids and not is_nil(ns.dataset_id) and
        ns.role == :producer and
        c.organization == ^current_contact.organization
    )
    # we shouldn’t take all and select better
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
    |> where([notification_subscription: ns], ns.id == ^subscription_id and ns.contact_id == ^current_contact.id)
    |> DB.Repo.one!()
    |> DB.Repo.delete!()
  end
end
