defmodule TransportWeb.Live.FollowDatasetLive do
  @moduledoc """
  A follow/unfollow button for dataset reusers.

  This button is displayed when:
  - the user is not authenticated: nudge to sign up/log in
  - the user is authenticated: follow the dataset and find it in the reuser space

  The button is not displayed when the user is a producer of the dataset
  (cannot be a reuser of your own dataset).
  """
  use Phoenix.LiveView
  import Ecto.Query
  import TransportWeb.Gettext, only: [dgettext: 3]
  import TransportWeb.Router.Helpers

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={is_nil(@current_user)} class="follow-dataset-icon">
      <i class={@heart_class} phx-click="nudge_signup"></i>
      <p :if={@display_banner?} class="notification active">
        <%= Phoenix.HTML.raw(
          dgettext(
            "page-dataset-details",
            ~s|<a href="%{url}">Log in or sign up</a> to benefit from dataset services.|,
            url: page_path(@socket, :login, redirect_path: dataset_path(@socket, :details, @dataset.slug))
          )
        ) %>
      </p>
    </div>
    <div :if={not is_nil(@current_user) and not @producer?} class="follow-dataset-icon">
      <i class={@heart_class} phx-click="toggle"></i>
      <p :if={@display_banner?} class="notification active">
        <%= Phoenix.HTML.raw(
          dgettext(
            "page-dataset-details",
            ~s|Dataset added to your favorites! Personalise your settings from your <a href="%{url}" target="_blank">reuser space</a>.|,
            url: reuser_space_path(@socket, :espace_reutilisateur)
          )
        ) %>
      </p>
    </div>
    """
  end

  @impl true
  def mount(_params, %{"current_user" => current_user, "dataset_id" => dataset_id}, socket) do
    socket =
      socket
      |> assign(%{
        display_banner?: false,
        contact: contact(current_user),
        dataset: DB.Repo.get!(DB.Dataset, dataset_id),
        current_user: current_user
      })
      |> set_computed_assigns()

    {:ok, socket}
  end

  defp set_computed_assigns(%Phoenix.LiveView.Socket{assigns: %{dataset: dataset, contact: contact}} = socket) do
    follows_dataset? = DB.DatasetFollower.follows_dataset?(contact, dataset)

    assign(socket, %{
      follows_dataset?: follows_dataset?,
      producer?: producer?(contact, dataset),
      heart_class: heart_class(follows_dataset?: follows_dataset?)
    })
  end

  @impl true
  def handle_event("nudge_signup", _, %Phoenix.LiveView.Socket{} = socket) do
    {:noreply, assign(socket, :display_banner?, true)}
  end

  @impl true
  def handle_event(
        "toggle",
        _,
        %Phoenix.LiveView.Socket{
          assigns: %{
            dataset: %DB.Dataset{} = dataset,
            contact: %DB.Contact{} = contact,
            follows_dataset?: follows_dataset?
          }
        } = socket
      ) do
    if follows_dataset? do
      DB.DatasetFollower.unfollow!(contact, dataset)
      delete_notification_subscriptions(contact, dataset)
    else
      maybe_promote_reuser_space(contact)
      DB.DatasetFollower.follow!(contact, dataset, source: :follow_button)
      create_notification_subscriptions(contact, dataset)
      # Hide banner after 10s
      Process.send_after(self(), :hide_banner, 10_000)
    end

    {:noreply, socket |> assign(:display_banner?, not follows_dataset?) |> set_computed_assigns()}
  end

  @impl true
  def handle_info(:hide_banner, %Phoenix.LiveView.Socket{} = socket) do
    {:noreply, assign(socket, :display_banner?, false)}
  end

  def maybe_promote_reuser_space(%DB.Contact{id: contact_id}) do
    already_followed_a_dataset? =
      DB.DatasetFollower
      |> where([df], df.contact_id == ^contact_id and df.source == :follow_button)
      |> DB.Repo.exists?()

    unless already_followed_a_dataset? do
      %{contact_id: contact_id}
      |> Transport.Jobs.PromoteReuserSpaceJob.new()
      |> Oban.insert!()
    end
  end

  defp create_notification_subscriptions(%DB.Contact{id: contact_id} = contact, %DB.Dataset{id: dataset_id}) do
    maybe_subscribe_to_daily_new_comments(contact)

    Enum.each(DB.NotificationSubscription.reasons_related_to_datasets(), fn reason ->
      DB.NotificationSubscription.insert!(%{
        contact_id: contact_id,
        dataset_id: dataset_id,
        reason: reason,
        source: :user,
        role: :reuser
      })
    end)
  end

  @doc """
  Subscribe the contact to the new comments daily digest:
  - if the user is not already subscribed
  - if the user does not have existing subscriptions (they likely deactivated this notification reason)
  """
  def maybe_subscribe_to_daily_new_comments(%DB.Contact{id: contact_id}) do
    subscribed_to_daily_new_comments? =
      DB.NotificationSubscription.base_query()
      |> where([notification_subscription: ns], ns.contact_id == ^contact_id and ns.reason == :daily_new_comments)
      |> DB.Repo.exists?()

    existing_subscriptions? =
      DB.NotificationSubscription.base_query()
      |> where(
        [notification_subscription: ns],
        ns.contact_id == ^contact_id and not is_nil(ns.dataset_id) and ns.role == :reuser
      )
      |> DB.Repo.exists?()

    if not subscribed_to_daily_new_comments? and not existing_subscriptions? do
      DB.NotificationSubscription.insert!(%{
        contact_id: contact_id,
        reason: :daily_new_comments,
        source: :user,
        role: :reuser
      })
    end
  end

  defp delete_notification_subscriptions(%DB.Contact{id: contact_id}, %DB.Dataset{id: dataset_id}) do
    DB.NotificationSubscription.base_query()
    |> where([notification_subscription: ns], ns.contact_id == ^contact_id and ns.dataset_id == ^dataset_id)
    |> DB.Repo.delete_all()
  end

  # Case where the user is not authenticated
  defp contact(nil = _current_user), do: nil

  defp contact(%{"id" => datagouv_user_id} = _current_user),
    do: DB.Repo.get_by!(DB.Contact, datagouv_user_id: datagouv_user_id)

  # Case where the user is not authenticated
  defp producer?(nil, _), do: false

  defp producer?(%DB.Contact{id: contact_id}, %DB.Dataset{organization_id: organization_id}) do
    DB.Contact.base_query()
    |> join(:inner, [contact: c], c in assoc(c, :organizations), as: :organization)
    |> where([contact: c, organization: o], c.id == ^contact_id and o.id == ^organization_id)
    |> DB.Repo.exists?()
  end

  defp heart_class(follows_dataset?: false), do: "fa fa-heart fa-2x icon---animated-heart"
  defp heart_class(follows_dataset?: true), do: heart_class(follows_dataset?: false) <> " active"
end