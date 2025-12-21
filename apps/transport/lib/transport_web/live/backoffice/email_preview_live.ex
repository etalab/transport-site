defmodule TransportWeb.Backoffice.EmailPreviewLive do
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import Ecto.Query
  import TransportWeb.Backoffice.JobsLive, only: [ensure_admin_auth_or_redirect: 3]
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers

  @impl true
  def mount(params, %{"current_user" => current_user, "csp_nonce_value" => nonce} = _session, socket) do
    {:ok,
     ensure_admin_auth_or_redirect(socket, current_user, fn socket ->
       contact = DB.Repo.get_by(DB.Contact, datagouv_user_id: current_user["id"])
       socket |> assign(contact: contact, selected_email: nil, search: params["search"], nonce: nonce) |> emails()
     end)}
  end

  def emails(%Phoenix.LiveView.Socket{assigns: %{contact: contact}} = socket) do
    [dataset, other_dataset] =
      DB.Dataset.base_query()
      |> preload(:resources)
      |> where([dataset: d], d.type == "public-transit")
      |> limit(2)
      |> DB.Repo.all()

    emails = [
      {:resources_changed, ["reuser", "notification"], Transport.UserNotifier.resources_changed(contact, dataset)},
      {:new_comments_reuser, ["reuser", "comments"],
       Transport.UserNotifier.new_comments_reuser(contact, [dataset, other_dataset])},
      {:new_comments_producer, ["producer", "comments"],
       Transport.UserNotifier.new_comments_producer(
         contact,
         2,
         [
           {:ok, dataset.datagouv_id, "Titre",
            [
              %{
                "posted_by" => %{"first_name" => "John", "last_name" => "Doe"},
                "content" => "Commentaire",
                "discussion_id" => "foo"
              }
            ]}
         ]
       )},
      {:promote_reuser_space, ["reuser"], Transport.UserNotifier.promote_reuser_space(contact)},
      {:dataset_now_on_nap, ["producer"], Transport.UserNotifier.dataset_now_on_nap(contact, dataset)},
      {:datasets_switching_climate_resilience_bill, ["reuser"],
       Transport.UserNotifier.datasets_switching_climate_resilience_bill(contact, [[:ok, dataset]], [[:ok, dataset]])},
      {:multi_validation_with_error_notification, ["producer", "notification", "error"],
       Transport.UserNotifier.multi_validation_with_error_notification(contact, :producer,
         dataset: dataset,
         resources: dataset.resources,
         validator_name: nil,
         job_id: nil
       )},
      {:multi_validation_with_error_notification, ["reuser", "notification", "error"],
       Transport.UserNotifier.multi_validation_with_error_notification(contact, :reuser,
         dataset: dataset,
         producer_warned: true,
         validator_name: nil,
         job_id: nil
       )},
      {:resource_unavailable, ["producer", "notification", "availability"],
       Transport.UserNotifier.resource_unavailable(contact, :producer,
         dataset: dataset,
         hours_consecutive_downtime: 42,
         deleted_recreated_on_datagouv: true,
         resource_titles: Enum.map_join(dataset.resources, ",", & &1.title),
         unavailabilities: nil,
         job_id: nil
       )},
      {:resource_unavailable, ["reuser", "notification", "availability"],
       Transport.UserNotifier.resource_unavailable(contact, :reuser,
         dataset: dataset,
         hours_consecutive_downtime: 42,
         producer_warned: true,
         resource_titles: Enum.map_join(dataset.resources, ",", & &1.title),
         unavailabilities: nil,
         job_id: nil
       )},
      {:periodic_reminder_producers_no_subscriptions, ["producer"],
       Transport.UserNotifier.periodic_reminder_producers_no_subscriptions(contact, [dataset, other_dataset])},
      {:periodic_reminder_producers_with_subscriptions, ["producer"],
       Transport.UserNotifier.periodic_reminder_producers_with_subscriptions(contact, [dataset, other_dataset], [
         contact
       ])},
      {:new_datasets, ["reuser"], Transport.UserNotifier.new_datasets(contact, [dataset, other_dataset])},
      {:expiration_producer, ["producer", "notification", "expiration"],
       Transport.UserNotifier.expiration_producer(contact, dataset, dataset.resources, 0)},
      {:expiration_reuser, ["reuser", "notification", "expiration"],
       Transport.UserNotifier.expiration_reuser(contact, "<p>Exemple de contenu</p>")},
      {:promote_producer_space, ["producer"], Transport.UserNotifier.promote_producer_space(contact)},
      {:warn_inactivity, ["contact"], Transport.UserNotifier.warn_inactivity(contact, "Dans 1 mois")}
    ]

    tags = Enum.flat_map(emails, &elem(&1, 1)) |> Enum.uniq() |> Enum.sort()

    socket |> assign(emails: emails, filtered_emails: emails, tags: tags)
  end

  @impl true
  def handle_event("see_email", %{"key_name" => key_name}, socket) do
    key_name = String.to_existing_atom(key_name)
    selected_email = Enum.find_value(socket.assigns.emails, fn {key, _tags, item} -> if key == key_name, do: item end)
    {:noreply, socket |> assign(selected_email: selected_email)}
  end

  @impl true
  def handle_event("change", %{"search" => search} = params, %Phoenix.LiveView.Socket{} = socket) do
    {:noreply, socket |> push_patch(to: backoffice_live_path(socket, __MODULE__, search: search))}
  end

  @impl true
  def handle_params(%{"search" => search} = params, _uri, socket) do
    {:noreply, socket |> filter_config(params)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  def filter_config(%Phoenix.LiveView.Socket{} = socket, %{"search" => search}) do
    socket |> assign(%{search: search}) |> filter_config()
  end

  defp filter_config(
         %Phoenix.LiveView.Socket{assigns: %{emails: emails, search: search}} =
           socket
       ) do
    socket |> assign(%{filtered_emails: emails |> filter_by_search(search)})
  end

  defp filter_by_search(config, ""), do: config

  defp filter_by_search(config, value) do
    Enum.filter(config, fn {identifier, tags, %Swoosh.Email{subject: subject}} ->
      Enum.any?([
        String.contains?(normalize(subject), normalize(value)),
        String.contains?(Enum.join(tags, ","), normalize(value)),
        String.contains?(normalize(identifier), normalize(value))
      ])
    end)
  end

  @doc """
  iex> normalize("Paris")
  "paris"
  iex> normalize("vélo")
  "velo"
  iex> normalize("Châteauroux")
  "chateauroux"
  iex> normalize(:alpha)
  "alpha"
  """
  def normalize(value) do
    value |> to_string() |> String.normalize(:nfd) |> String.replace(~r/[^A-z]/u, "") |> String.downcase()
  end
end
