defmodule TransportWeb.NewCoveredAreaSelectLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  # import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <%= for covered_area <- @new_covered_area do %>
        <%= covered_area.nom %>
      <% end %>
      <label>
        Une ou plusieurs communes, EPCI, département, région <%= InputHelpers.text_input(@form, :legal_owner_input,
          placeholder: "Paris",
          list: "covered_area_suggestions",
          phx_keydown: "add_or_suggest_division",
          phx_target: @myself,
          id: "new_covered_area_input"
        ) %>
      </label>
      <div class="autoCompleteResultsField" id="covered_area_suggestions" :if={@matches != []}>
        <div id="autoCompleteResults">
          <ul id="autoComplete_list">
          <li class="autoComplete_result"></li>
          <li class="autoComplete_result"></li>
            <%= for match <- @matches do %>
              <li class="autoComplete_result"><div>
              <span class="autocomplete_name"><%= match.nom %></span>
              <span class="autocomplete_type"><%= division_name(match) %></span>
              </div></li>
            <% end %>
          </ul>
        </div>
      </div>
      <div class="pt-6"></div>
    </div>
    """
  end

  def mount(socket) do
    {:ok, socket |> assign(matches: [])}
  end

  def update(assigns, socket) do
    administrative_divisions = DB.DatasetNewCoveredArea.load_searchable_administrative_divisions()

    {:ok, socket |> assign(assigns) |> assign(:administrative_divisions, administrative_divisions)}
  end

  def handle_event("add_or_suggest_division", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, matches: [])}
  end


  def handle_event("add_or_suggest_division", %{"value" => ""}, socket) do
    {:noreply, assign(socket, matches: [])}
  end

  def handle_event("add_or_suggest_division", %{"value" => query}, socket) when byte_size(query) <= 100 do
    matches =
      socket.assigns.administrative_divisions
      |> DB.DatasetNewCoveredArea.search(query)
      |> Enum.take(5)

    {:noreply, assign(socket, matches: matches)}
  end

  def handle_event("add_or_suggest_division", _, socket) do
    {:noreply, socket}
  end

  # TODO : event
  def handle_event("remove_tag", %{"owner-id" => owner_id, "owner-type" => owner_type}, socket) do
    owners =
      socket.assigns.owners
      |> Enum.reject(fn owner -> owner.id == String.to_integer(owner_id) and owner.type == owner_type end)

    send(self(), {:updated_legal_owner, owners})

    {:noreply, socket}
  end

  # clear the input using a js hook
  # TODO: change that
  def clear_input(socket) do
    push_event(socket, "backoffice-form-owner-reset", %{})
  end

  def division_display_name(%{nom: nom, __struct__: type}) do
    types_display = %{
      DB.Commune => "Commune",
      DB.EPCI => "EPCI",
      DB.Departement => "Département",
      DB.Region => "Région"
    }

    "#{types_display[type]} : #{nom}"
  end

  def division_name(%{__struct__: DB.Commune}), do: "Commune"
  def division_name(%{__struct__: DB.EPCI}), do: "EPCI"
  def division_name(%{__struct__: DB.Departement}), do: "Département"
  def division_name(%{__struct__: DB.Region}), do: "Région"

  def color_class(%{type: "aom"}), do: "green"
  def color_class(%{type: "region"}), do: "blue"
end
