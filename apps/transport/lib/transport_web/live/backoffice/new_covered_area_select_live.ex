defmodule TransportWeb.NewCoveredAreaSelectLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  # import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <label>
        Une ou plusieurs communes, EPCI, département, région <%= InputHelpers.text_input(@form, :legal_owner_input,
          placeholder: "Paris",
          list: "covered_area_suggestions",
          phx_keydown: "search_division",
          phx_target: @myself,
          id: "new_covered_area_input"
        ) %>
      </label>
      <div :if={@matches != []} class="autoCompleteResultsField" id="covered_area_suggestions">
        <div id="autoCompleteResults">
          <ul id="autoComplete_list">
            <li class="autoComplete_result"></li>
            <li class="autoComplete_result"></li>
            <%= for match <- @matches do %>
              <li
                class="autoComplete_result"
                phx-target={@myself}
                phx-click="select_division"
                phx-value-insee={match.insee}
                phx-value-type={match.type}
                }
              >
                <div>
                  <span class="autocomplete_name"><%= match.nom %></span>
                  <span class="autocomplete_type"><%= type_display(match) %></span>
                </div>
              </li>
            <% end %>
          </ul>
        </div>
      </div>
      <div :for={{division, index} <- Enum.with_index(@new_covered_area)} class="pt-6">
        <span class={["label", "custom-tag"]}>
          <%= division.nom %> (<%= division.type %>)
          <span
            class="delete-tag"
            phx-click="remove_tag"
            phx-value-insee={division.insee}
            phx-value-type={division.type}
            phx-target={@myself}
          >
          </span>
        </span>
        <%= Phoenix.HTML.Form.hidden_input(@form, "new_covered_area_#{division.type}_#{index}", value: division.insee) %>
      </div>
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

  def handle_event("search_division", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, matches: [])}
  end

  def handle_event("search_division", %{"value" => ""}, socket) do
    {:noreply, assign(socket, matches: [])}
  end

  def handle_event("search_division", %{"value" => query}, socket) when byte_size(query) <= 100 do
    matches =
      socket.assigns.administrative_divisions
      |> DB.DatasetNewCoveredArea.search(query)
      |> Enum.take(5)

    {:noreply, assign(socket, matches: matches)}
  end

  def handle_event("search_division", _, socket) do
    {:noreply, socket}
  end

  def handle_event("select_division", %{"insee" => insee, "type" => type}, socket) do
    division = DB.DatasetNewCoveredArea.get_administrative_division(insee, type)

    new_covered_area = socket.assigns.new_covered_area ++ [division]

    send(self(), {:updated_new_covered_area, new_covered_area})

    {:noreply, socket |> assign(matches: []) |> clear_input()}
  end

  # TODO : event
  def handle_event("remove_tag", %{"insee" => insee, "type" => type}, socket) do
    new_covered_area =
      socket.assigns.new_covered_area
      |> Enum.reject(fn division -> division.insee == insee and division.type == type end)

    send(self(), {:updated_new_covered_area, new_covered_area})

    {:noreply, socket}
  end

  # clear the input using a js hook
  # TODO: change that
  @spec clear_input(Phoenix.LiveView.Socket.t()) :: map()
  def clear_input(socket) do
    push_event(socket, "backoffice-form-covered-area-reset", %{})
  end

  # TODO: probably not needed
  def division_display_name(%{nom: nom, type: type}) do
    types_display = %{
      "commune" => "Commune",
      "epci" => "EPCI",
      "departement" => "Département",
      "region" => "Région"
    }

    "#{types_display[type]} : #{nom}"
  end

  def type_display(%{type: "commune"}), do: "Commune"
  def type_display(%{type: "epci"}), do: "EPCI"
  def type_display(%{type: "departement"}), do: "Département"
  def type_display(%{type: "region"}), do: "Région"

  #  TODO: put colored tags
  def color_class(%{type: "aom"}), do: "green"
  def color_class(%{type: "region"}), do: "blue"
end
