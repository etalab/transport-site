defmodule TransportWeb.ProxyRequestsCountLive do
  @moduledoc """
  A live counter of dicussions for the dataset
  """
  use Phoenix.LiveView, container: {:div, [class: "domain", id: "proxy-requests"]}
  import Ecto.Query

  @doc_url "https://doc.transport.data.gouv.fr/foire-aux-questions-1/donnees-temps-reel-des-transports-en-commun#proxy-gtfs-rt"

  def render(assigns) do
    ~H"""
    <h2>Requêtes temps-réel sur le proxy</h2>
    <p>
      transport.data.gouv.fr met à disposition des producteurs de données <a href={@doc_url}>un service de proxy</a>
      permettant de diffuser des données temps réel aux formats GTFS-RT, GBFS et SIRI.
    </p>
    <div :if={assigns[:data]}>
      <% ratio = Map.get(assigns[:data], "external", 0) / Map.get(assigns[:data], "internal", 1) %>
      <div class="proxy-external-requests"><%= Helpers.format_number(Map.get(assigns[:data], "external", 0)) %></div>
      <div class="proxy-legend">Nombre de requêtes au cours des 30 derniers jours</div>
      <p>
        Ce service facilite la diffusion de données temps réel et diminue
        les coûts de mise à disposition des producteurs.
        Notre proxy a diminué le nombre de requêtes que doivent gérer les producteurs
        par un facteur de <%= ratio |> Float.round(1) |> Helpers.format_number() %> sur cette période.
      </p>
    </div>
    """
  end

  def mount(_, _, socket) do
    send(self(), :update_data)
    {:ok, socket |> assign(:doc_url, @doc_url)}
  end

  def handle_info(:update_data, socket) do
    query =
      from(m in DB.Metrics,
        group_by: [fragment("case when ? like '%internal' then 'internal' else 'external' end", m.event)],
        where: fragment("? >= (now() - interval '30 day')", m.period),
        where: fragment("? ~ ':(internal|external)$'", m.event),
        select: %{
          sum: sum(m.count),
          event: fragment("case when ? like '%internal' then 'internal' else 'external' end", m.event)
        }
      )

    socket =
      socket
      |> assign(:data, query |> DB.Repo.all() |> Enum.into(%{}, fn %{event: event, sum: sum} -> {event, sum} end))

    Process.send_after(self(), :update_data, 5_000)
    {:noreply, socket}
  end
end
