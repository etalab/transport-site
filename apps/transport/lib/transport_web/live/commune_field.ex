defmodule TransportWeb.Live.CommuneField do
  @moduledoc """
  Field with autocomplete to find INSEE code
  """
  use Phoenix.LiveComponent
  alias Transport.SearchCommunes
  alias TransportWeb.InputHelpers

  def render(assigns) do
    ~H"""
    <div>
      <%= InputHelpers.text_input(@form, :insee,
        placeholder: "Commune faisant partie de l'AOM (code INSEE ou nom)",
        value: @insee,
        phx_keyup: "suggest",
        list: "matches",
        autocomplete: "off",
        id: "communes_q",
        phx_target: @myself
      ) %>
      <datalist id="matches">
        <%= for match <- @matches do %>
          <option value={match.insee}><%= "#{match.nom} #{match.insee}" %></option>
        <% end %>
      </datalist>
    </div>
    """
  end

  def mount(socket) do
    {:ok, socket |> assign(matches: [])}
  end

  def handle_event("suggest", %{"value" => query}, socket) when byte_size(query) <= 100 do
    matches =
      query
      |> SearchCommunes.search()
      |> Enum.take(5)

    {:noreply, assign(socket, matches: matches)}
  end
end
