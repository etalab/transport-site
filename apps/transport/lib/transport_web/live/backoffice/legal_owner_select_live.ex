defmodule TransportWeb.LegalOwnerSelectLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <label>
        Une/des AOM locale(s) ou régionale(s) <%= InputHelpers.text_input(@form, :legal_owner_input,
          placeholder: "CC du Val de Morteau",
          list: "owner_suggestions",
          phx_keydown: "add_tag",
          phx_target: @myself,
          id: "js-owner-input"
        ) %>
      </label>
      <datalist id="owner_suggestions" phx-keydown="add_tag">
        <%= for owner_suggestion <- @owners_list do %>
          <option value={owner_label(owner_suggestion)}><%= owner_label(owner_suggestion) %></option>
        <% end %>
      </datalist>
      <div class="pt-6">
        <%= for {owner, index} <- Enum.with_index(@owners) do %>
          <span class={["label", "custom-tag"] ++ [color_class(owner)]}>
            <%= owner_label(owner, @owners_list) %>
            <span
              class="delete-tag"
              phx-click="remove_tag"
              phx-value-owner-id={owner.id}
              phx-value-owner-type={owner.type}
              phx-target={@myself}
            >
            </span>
          </span>
          <% {field_name, field_value} = field_info(owner, index) %>
          <%= Phoenix.HTML.Form.hidden_input(@form, field_name, value: field_value) %>
        <% end %>
      </div>
    </div>
    """
  end

  def update(assigns, socket) do
    aoms = DB.AOM |> select([aom], %{label: aom.nom, type: "aom", id: aom.id})
    regions = DB.Region |> select([r], %{label: r.nom, type: "region", id: r.id})

    owners_list = aoms |> union_all(^regions) |> DB.Repo.all()

    removed_aoms =
      Map.get(socket.assigns, :removed, [])
      |> Enum.filter(&(&1["owner-type"] == "aom"))
      |> Enum.map(&String.to_integer(&1["owner-id"]))

    aoms_from_offers = assigns.offers |> Enum.map(& &1.aom_id) |> Enum.reject(&(&1 in removed_aoms))
    owners = (assigns.owners ++ Enum.filter(owners_list, &(&1.id in aoms_from_offers and &1.type == "aom"))) |> Enum.uniq()

    {:ok, socket |> assign(assigns) |> assign(%{owners_list: owners_list, owners: owners})}
  end

  def handle_event("add_tag", %{"key" => "Enter", "value" => value}, socket) do
    new_owner = Enum.find(socket.assigns.owners_list, fn owner -> owner_label(owner) == value end)
    legal_owners = (socket.assigns.owners ++ [new_owner]) |> Enum.uniq()

    if is_nil(new_owner) do
      {:noreply, socket}
    else
      # new owners list is sent to the parent liveview form
      # because this is a LiveComponent, the process of the parent is the same.
      send(self(), {:updated_legal_owner, legal_owners})
      {:noreply, socket |> clear_input()}
    end
  end

  def handle_event("add_tag", _, socket) do
    {:noreply, socket}
  end

  def handle_event("remove_tag", %{"owner-id" => owner_id, "owner-type" => owner_type} = value, socket) do
    owners =
      socket.assigns.owners
      |> Enum.reject(fn owner -> owner.id == String.to_integer(owner_id) and owner.type == owner_type end)

    send(self(), {:updated_legal_owner, owners})

    removed = Map.get(socket.assigns, :removed, []) ++ [value]

    {:noreply, socket |> assign(%{removed: removed, owners: owners})}
  end

  # clear the input using a js hook
  def clear_input(socket) do
    push_event(socket, "backoffice-form-owner-reset", %{})
  end

  def field_info(owner, index) do
    {"legal_owners_#{owner.type}[#{index}]", owner.id}
  end

  def owner_label(%{label: label, type: type}) do
    types_display = %{"aom" => "AOM", "region" => "Région"}
    "#{types_display[type]} : #{label}"
  end

  def owner_label(%{type: type, id: id}, owners_list) do
    owners_list
    |> Enum.find(fn owner -> owner.type == type and owner.id == id end)
    |> owner_label()
  end

  def color_class(%{type: "aom"}), do: "green"
  def color_class(%{type: "region"}), do: "blue"
end
