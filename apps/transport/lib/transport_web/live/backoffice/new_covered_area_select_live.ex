defmodule TransportWeb.NewCoveredAreaSelectLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  # import Ecto.Query

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <label>
        Une ou plusieurs communes, EPCI, département, région <%= InputHelpers.text_input(@form, :new_covered_areas_input,
          placeholder: "Paris",
          list: "covered_area_suggestions",
          phx_keydown: "search_division",
          phx_target: @myself,
          id: "new_covered_areas_input"
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
                phx-value-type={match.administrative_division_type}
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
        <span class={["label", "custom-tag"] ++ [color_class(division)]}>
          <%= division.nom %> (<%= division.administrative_division_type %>)
          <span
            class="delete-tag"
            phx-click="remove_tag"
            phx-value-insee={division.insee}
            phx-value-type={division.administrative_division_type}
            phx-target={@myself}
          >
          </span>
        </span>
        <%= Phoenix.HTML.Form.hidden_input(@form, "new_covered_area_#{division.administrative_division_type}_#{index}",
          value: division.insee
        ) %>
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
    # TODO: eventually switch rather to ID
    division = DB.DatasetNewCoveredArea.get_administrative_division(insee, type)

    new_covered_area = socket.assigns.new_covered_area ++ [division]

    send(self(), {:updated_new_covered_area, new_covered_area})

    {:noreply, socket |> assign(matches: []) |> clear_input()}
  end

  # TODO : event
  def handle_event("remove_tag", %{"insee" => insee, "type" => type}, socket) do
    new_covered_area =
      socket.assigns.new_covered_area
      |> Enum.reject(fn division ->
        division.insee == insee and division.administrative_division_type == String.to_atom(type)
      end)

    send(self(), {:updated_new_covered_area, new_covered_area})

    {:noreply, socket}
  end

  # clear the input using a js hook
  @spec clear_input(Phoenix.LiveView.Socket.t()) :: map()
  def clear_input(socket) do
    # TODO: this doesn’t work as the "change_dataset" event is sent right after and contains the old value
    push_event(socket, "backoffice-form-covered-area-reset", %{})
  end

  def type_display(%{administrative_division_type: :commune}), do: "Commune"
  def type_display(%{administrative_division_type: :epci}), do: "EPCI"
  def type_display(%{administrative_division_type: :departement}), do: "Département"
  def type_display(%{administrative_division_type: :region}), do: "Région"

  #  TODO: put colored tags
  def color_class(%{administrative_division_type: :commune}), do: "green"
  def color_class(%{administrative_division_type: :epci}), do: "blue"
  def color_class(%{administrative_division_type: :departement}), do: "red"
  def color_class(%{administrative_division_type: :region}), do: "black"
end
