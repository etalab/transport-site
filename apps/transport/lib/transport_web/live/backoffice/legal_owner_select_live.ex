defmodule TransportWeb.LegalOwnerSelectLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <div class="pb-6">
        <%= for {owner_display_label, index} <- Enum.with_index(@owners) do %>
          <span class={["label", "custom-tag"] ++ [color_class(owner_display_label)]}>
            <%= owner_display_label %> <span class="delete-tag" phx-click="remove_tag" phx-value-owner={owner_display_label} phx-target={@myself}></span>
          </span>
          <% {field_name, field_value} = get_field_info(owner_display_label, index, @owners_list) %>
          <%= Phoenix.HTML.Form.hidden_input(@form, field_name, value: field_value) %>
        <% end %>
      </div>
      <%= InputHelpers.text_input(@form, :tag_input,
        placeholder: "Ajouter un représentant légal (AOM locale ou régionale)",
        list: "owner_suggestions",
        phx_keydown: "add_tag",
        phx_target: @myself,
        id: "owner_input"
      ) %>
      <datalist id="owner_suggestions" phx-keydown="add_tag">
        <%= for owner_suggestion <- @owners_list do %>
          <option value={owner_display(owner_suggestion)}><%= owner_display(owner_suggestion) %></option>
        <% end %>
      </datalist>
    </div>
    """
  end

  def update(assigns, socket) do
    aoms = DB.AOM |> select([aom], %{label: aom.nom, type: "AOM", id: aom.id})
    regions = DB.Region |> select([r], %{label: r.nom, type: "Région", id: r.id})

    owners_list =
      aoms
      |> union_all(^regions)
      |> DB.Repo.all()

    {:ok, socket |> assign(assigns) |> assign(:owners_list, owners_list)}
  end

    def handle_event("add_tag", %{"key" => "Enter", "value" => value}, socket) do
      if Enum.any?(socket.assigns.owners_list, fn owner -> owner_display(owner) == value end) do
        owners = (socket.assigns.owners ++ [value]) |> Enum.uniq()
        socket = socket |> clear_input() |> assign(:owners, owners)

        {:noreply, socket}
    else
      {:noreply, socket}
    end
    end

    def handle_event("add_tag", _, socket) do
      {:noreply, socket}
    end

    def handle_event("remove_tag", %{"owner" => owner}, socket) do
      owners = socket.assigns.owners -- [owner]
      {:noreply, assign(socket, :owners, owners)}
    end

    def clear_input(socket) do
      push_event(socket, "backoffice-form-owner-reset", %{})
    end

    def get_field_info(owner_display_label, index, owners) do
      owner = owners |> Enum.find(fn owner -> owner_display(owner) == owner_display_label end)
      {"owners_#{owner.type}[#{index}]", owner.id}
    end

    def color_class("AOM : " <> _), do: "green"
    def color_class("Région : " <> _), do: "blue"

    def owner_display(%{label: label, type: type}), do: "#{type} : #{label}"
end
