defmodule TransportWeb.NotificationLive do
  use Phoenix.LiveView
  import Ecto.Query
  use TransportWeb.InputHelpers
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers
  import TransportWeb.Gettext

  def mount(
        _params,
        %{
          "current_user" => current_user,
          "locale" => locale
        },
        socket
      ) do
    # The following thing calls datagouv to get the org of the user, then the datasets of the org
    # Shouldn’t we just update the orgs of the contact in database and use that instead?
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
      # |> assign(:current_user, current_user)
      |> assign(:locale, locale)
      |> assign(:datasets, datasets)
      |> assign(:subscriptions, subscriptions)

    {:ok, socket}
  end

  def handle_event("toggle", %{"dataset-id" => dataset_id, "reason" => reason}, socket) do
    # toggle_subscription(id)

    # {:noreply, assign(socket, :subscriptions, fetch_subscriptions())} TODO
    {:noreply, socket}
  end

  defp notification_subscriptions_for_datasets(datasets, current_contact) do
    dataset_ids = datasets |> Enum.map(& &1.id)

    subscriptions_list = load_subscriptions_for_datasets_and_contact(dataset_ids, current_contact)

    subscriptions_list
    |> Enum.sort_by(&{&1.dataset.custom_title, &1.reason})
    |> Enum.group_by(& &1.dataset.id)
    |> Map.new(fn {dataset, subscriptions} -> {dataset, group_by_reason_and_contact(subscriptions, current_contact)} end)
  end

  defp load_subscriptions_for_datasets_and_contact(dataset_ids, current_contact) do
    DB.NotificationSubscription.base_query()
    |> DB.NotificationSubscription.join_with_contact()
    |> preload(:contact)
    |> preload(:dataset)
    |> where(
      [notification_subscription: ns, contact: c],
      # That’s not so good, it’s just a string
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

  defp toggle_subscription(id) do
    # Toggle the subscription with the given ID
    # Replace this with your actual code to toggle the subscription
  end
end
