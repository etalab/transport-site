defmodule TransportWeb.Live.FollowDatasetLive do
  @moduledoc """
  A follow/unfollow button for datasets
  """
  use Phoenix.LiveView
  import Ecto.Query

  @impl true
  def render(assigns) do
    ~H"""
    <div :if={not is_nil(@current_user) and not @is_producer} class="follow-dataset-icon">
      <i class={@heart_class} phx-click="toggle"></i>
    </div>
    """
  end

  @impl true
  def mount(_params, %{"current_user" => current_user, "dataset_id" => dataset_id}, socket) do
    contact = contact(current_user)
    dataset = DB.Repo.get!(DB.Dataset, dataset_id)
    follows_dataset = DB.DatasetFollower.follows_dataset?(contact, dataset)

    socket =
      assign(socket, %{
        contact: contact,
        dataset: dataset,
        current_user: current_user,
        follows_dataset: follows_dataset,
        is_producer: producer?(contact, dataset),
        heart_class: heart_class(follows_dataset: follows_dataset)
      })

    {:ok, socket}
  end

  @impl true
  def handle_event(
        "toggle",
        _,
        %Phoenix.LiveView.Socket{
          assigns: %{
            dataset: %DB.Dataset{} = dataset,
            contact: %DB.Contact{} = contact,
            follows_dataset: follows_dataset
          }
        } = socket
      ) do
    if follows_dataset do
      DB.DatasetFollower.unfollow!(contact, dataset)
    else
      DB.DatasetFollower.follow!(contact, dataset, source: :follow_button)
    end

    {:noreply,
     assign(socket, %{
       follows_dataset: not follows_dataset,
       heart_class: heart_class(follows_dataset: not follows_dataset)
     })}
  end

  defp contact(nil = _current_user), do: nil

  defp contact(%{"id" => datagouv_user_id} = _current_user),
    do: DB.Repo.get_by!(DB.Contact, datagouv_user_id: datagouv_user_id)

  defp producer?(nil, _), do: false

  defp producer?(%DB.Contact{id: contact_id}, %DB.Dataset{organization_id: organization_id}) do
    DB.Contact.base_query()
    |> join(:inner, [contact: c], c in assoc(c, :organizations), as: :organization)
    |> where([contact: c, organization: o], c.id == ^contact_id and o.id == ^organization_id)
    |> DB.Repo.exists?()
  end

  defp heart_class(follows_dataset: false), do: "fa fa-heart fa-2x icon---animated-heart"
  defp heart_class(follows_dataset: true), do: heart_class(follows_dataset: false) <> " active"
end
