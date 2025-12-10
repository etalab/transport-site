defmodule TransportWeb.OfferSelectLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <label>
        Offre de transport <%= InputHelpers.text_input(@form, :offer_input,
          placeholder: "Astuce",
          list: "offers",
          phx_keydown: "add_offer",
          phx_target: @myself,
          id: "js-offer-input"
        ) %>
      </label>
      <datalist id="offers" phx-keydown="add_offer">
        <%= for offer <- @offers_list do %>
          <option value={offer.id}><%= display(offer) %></option>
        <% end %>
      </datalist>
      <div class="pt-6">
        <%= for {offer, index} <- @offers |> Enum.sort_by(& &1.label) |> Enum.with_index() do %>
          <span class="label custom-tag">
            <%= display(offer) %>
            <span class="delete-tag" phx-click="remove_offer" phx-value-offer-id={offer.id} phx-target={@myself}></span>
          </span>
          <% {field_name, field_value} = field_info(offer, index) %>
          <%= Phoenix.HTML.Form.hidden_input(@form, field_name, value: field_value) %>
        <% end %>
      </div>
    </div>
    """
  end

  def update(assigns, socket) do
    offers =
      DB.Offer
      |> select([o], [:id, :nom_aom, :nom_commercial, :aom_id])
      |> DB.Repo.all()
      |> Enum.map(&serialize/1)

    {:ok, socket |> assign(assigns) |> assign(:offers_list, offers)}
  end

  def handle_event("add_offer", %{"key" => "Enter", "value" => value}, socket) do
    new_offer = Enum.find(socket.assigns.offers_list, &(&1.id == String.to_integer(value)))
    offers = (socket.assigns.offers ++ [new_offer]) |> Enum.uniq()

    if is_nil(new_offer) do
      {:noreply, socket}
    else
      # new offers list is sent to the parent liveview form
      # because this is a LiveComponent, the process of the parent is the same.
      send(self(), {:updated_offers, offers})
      {:noreply, socket |> clear_input()}
    end
  end

  def handle_event("add_offer", _, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_offer", %{"offer-id" => offer_id}, socket) do
    offers = Enum.reject(socket.assigns.offers, &(&1.id == String.to_integer(offer_id)))

    send(self(), {:updated_offers, offers})

    {:noreply, socket}
  end

  # clear the input using a js hook
  def clear_input(socket) do
    push_event(socket, "backoffice-form-offer-reset", %{})
  end

  def serialize(%DB.Offer{} = offer) do
    %{
      id: offer.id,
      label: offer.nom_commercial,
      nom_aom: offer.nom_aom,
      aom_id: offer.aom_id
    }
  end

  def display(%{label: label, nom_aom: nom_aom}), do: "#{label} (#{nom_aom})"
  def field_info(offer, index), do: {"offers[#{index}]", offer.id}
end
