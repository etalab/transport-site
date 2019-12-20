defmodule TransportWeb.Live.CommuneField do
  @moduledoc """
  Field with autocomplete to find INSEE code
  """
  use Phoenix.LiveView
  alias Transport.SearchCommunes

  def render(assigns) do
    ~L"""
    <div class="form__group">
        <input type="text" phx-keyup="suggest" list="matches" name="insee"
         autocomplete="off" id="communes_q" placeholder="Code INSEE (vous pouvez aussi chercher par nom)">
        <datalist id="matches">
        <%= for match <- @matches do %>
            <option value="<%= match.insee %>"><%= "#{match.nom} #{match.insee}" %></option>
        <% end %>
        </datalist>
    </div>
    """
  end

  def mount(_session, socket), do: {:ok, assign(socket, matches: [])}

  def handle_event("suggest", %{"value" => query}, socket) when byte_size(query) <= 100 do
    matches =
      query
      |> SearchCommunes.search()
      |> Enum.take(5)

    {:noreply, assign(socket, matches: matches)}
  end
end
