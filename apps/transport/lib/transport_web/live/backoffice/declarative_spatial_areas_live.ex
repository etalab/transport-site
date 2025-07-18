defmodule TransportWeb.DeclarativeSpatialAreasLive do
  use Phoenix.LiveComponent
  alias TransportWeb.InputHelpers
  use Gettext, backend: TransportWeb.Gettext

  def render(assigns) do
    ~H"""
    <div class="pt-24">
      <label>
        <%= dgettext("backoffice", "spatial areas label") %>
      </label>
      <%= InputHelpers.text_input(
        @form,
        :spatial_areas_search_input,
        placeholder: "Paris",
        phx_keydown: "search_division",
        phx_target: @myself,
        id: "spatial_areas_search_input"
      ) %>
      <div
        :if={@administrative_division_search_matches != []}
        class="autoCompleteResultsField"
        id="administrative_divisions_suggestions"
      >
        <div id="autoCompleteResults">
          <ul id="autoComplete_list">
            <li class="autoComplete_result"></li>
            <li class="autoComplete_result"></li>
            <%= for match <- @administrative_division_search_matches do %>
              <li class="autoComplete_result" phx-target={@myself} phx-click="select_division" phx-value-id={match.id} }>
                <div>
                  <span class="autocomplete_name"><%= match.nom %></span>
                  <span class="autocomplete_type">
                    <%= match.insee %> – <%= DB.AdministrativeDivision.display_type(match) %>
                  </span>
                </div>
              </li>
            <% end %>
          </ul>
        </div>
      </div>

      <div :for={{division, index} <- Enum.with_index(@declarative_spatial_areas)} class="pt-6">
        <span class={["label", "custom-tag"] ++ [color_class(division)]}>
          <%= division.nom %> (<%= division.insee %> – <%= DB.AdministrativeDivision.display_type(division) %>)
          <span class="delete-tag" phx-click="remove_division" phx-value-id={division.id} phx-target={@myself}></span>
        </span>
        <%= Phoenix.HTML.Form.hidden_input(@form, "declarative_spatial_area_#{index}", value: division.id) %>
      </div>
    </div>
    """
  end

  def mount(socket) do
    searchable_administrative_divisions = DB.AdministrativeDivision.load_searchable_administrative_divisions()

    socket =
      socket
      |> assign(
        :searchable_administrative_divisions,
        searchable_administrative_divisions
      )
      |> assign(:administrative_division_search_matches, [])

    {:ok, socket}
  end

  def handle_event("search_division", %{"key" => "Escape"}, socket) do
    {:noreply, assign(socket, administrative_division_search_matches: [])}
  end

  def handle_event("search_division", %{"value" => ""}, socket) do
    {:noreply, assign(socket, matches: [])}
  end

  def handle_event("search_division", %{"value" => query}, socket) when byte_size(query) <= 100 do
    matches =
      socket.assigns.searchable_administrative_divisions
      |> DB.AdministrativeDivision.search(query)
      |> Enum.take(5)

    {:noreply, assign(socket, administrative_division_search_matches: matches)}
  end

  def handle_event("search_division", _, socket) do
    {:noreply, socket}
  end

  def handle_event("select_division", %{"id" => id}, socket) do
    division = DB.AdministrativeDivision |> DB.Repo.get!(id)

    declarative_spatial_areas = socket.assigns.declarative_spatial_areas ++ [division]

    send(self(), {:updated_spatial_areas, declarative_spatial_areas})

    {:noreply, socket |> assign(administrative_division_search_matches: [])}
  end

  def handle_event("remove_division", %{"id" => id}, socket) do
    declarative_spatial_areas =
      socket.assigns.declarative_spatial_areas
      |> Enum.reject(fn division ->
        division.id == String.to_integer(id)
      end)

    send(self(), {:updated_spatial_areas, declarative_spatial_areas})

    {:noreply, socket}
  end

  def clear_input(socket) do
    # TODO: this doesn’t work, the input is not cleared
    push_event(socket, "backoffice-form-spatial-areas-reset", %{})
  end

  defp color_class(%DB.AdministrativeDivision{type: :commune}), do: "green"
  defp color_class(%DB.AdministrativeDivision{type: :epci}), do: "blue"
  defp color_class(%DB.AdministrativeDivision{type: :departement}), do: "orange"
  defp color_class(%DB.AdministrativeDivision{type: :region}), do: "grey"
  defp color_class(%DB.AdministrativeDivision{type: :pays}), do: "red"
end
