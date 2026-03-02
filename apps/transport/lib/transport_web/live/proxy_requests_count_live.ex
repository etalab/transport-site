defmodule TransportWeb.ProxyRequestsCountLive do
  @moduledoc """
  A live counter of dicussions for the dataset
  """
  use Phoenix.LiveView, container: {:div, [class: "domain", id: "proxy-requests"]}
  import Ecto.Query

  @doc_url "https://doc.transport.data.gouv.fr/type-donnees/operateurs-de-transport-regulier-de-personnes/administration-des-donnees-transport-public-collectif/publier-des-donnees-temps-reel/serveur-proxy-gtfs-rt"

  def render(assigns) do
    ~H"""
    <h2>Requêtes temps-réel sur le proxy</h2>
    <p>
      transport.data.gouv.fr met à disposition des producteurs de données <a href={@doc_url}>un service de proxy</a>
      permettant de diffuser des données temps réel au format GTFS-RT.
    </p>
    <div :if={assigns[:data]}>
      <% ratio = Map.get(assigns[:data], "external", 0) / Map.get(assigns[:data], "internal", 1) %>
      <div class="proxy-external-requests">
        {Helpers.format_number(Map.get(assigns[:data], "external", 0), locale: @locale)}
      </div>
      <div class="proxy-legend">Nombre de requêtes au cours des 30 derniers jours</div>
      <p>
        Ce service facilite la diffusion de données temps réel et diminue
        les coûts de mise à disposition des producteurs.
        Notre proxy a diminué le nombre de requêtes que doivent gérer les producteurs
        par un facteur de {ratio |> Float.round(1) |> Helpers.format_number(locale: @locale)} sur cette période.
      </p>
    </div>
    """
  end

  def mount(_, %{"locale" => locale}, socket) do
    send(self(), :update_data)
    {:ok, socket |> assign(doc_url: @doc_url, locale: locale)}
  end

  def handle_info(:update_data, socket) do
    query =
      from(m in DB.Metrics,
        group_by: fragment("event_type"),
        where: fragment("? >= (now() - interval '30 day')", m.period),
        select: %{
          sum: sum(m.count),
          event_type:
            fragment(
              "case when ? like '%internal' then 'internal' when ? like '%external' then 'external' else 'other' end",
              m.event,
              m.event
            )
        }
      )

    query =
      from(metrics in subquery(query),
        where: metrics.event_type != "other",
        select: %{
          sum: metrics.sum,
          event: metrics.event_type
        }
      )

    socket =
      socket
      |> assign(:data, query |> DB.Repo.all() |> Enum.into(%{}, fn %{event: event, sum: sum} -> {event, sum} end))

    Process.send_after(self(), :update_data, 5_000)
    {:noreply, socket}
  end
end
