defmodule TransportWeb.ReusesLive do
  @moduledoc """
  Display data.gouv reuses on the dataset page
  """
  use Phoenix.LiveView
  use Gettext, backend: TransportWeb.Gettext
  alias TransportWeb.MarkdownHandler

  def render(assigns) do
    ~H"""
    <%= unless @loading do %>
      <%= unless @reuses == [] and !@fetch_reuses_error do %>
        <section class="white pt-48" id="dataset-reuses">
          <h2><%= dgettext("page-dataset-details", "Reuses") %></h2>
          <%= if @fetch_reuses_error do %>
            <div class="panel reuses_not_available">
              🔌 <%= dgettext("page-dataset-details", "Reuses are temporarily unavailable") %>
            </div>
          <% end %>
          <div class="reuses">
            <%= for reuse <- @reuses do %>
              <div class="panel reuse">
                <img src={reuse["image"]} alt={reuse["title"]} />
                <div class="reuse__links">
                  <.link href={reuse["url"]}><%= dgettext("page-dataset-details", "Website") %></.link>
                  <.link href={reuse["page"]} target="_blank">
                    <%= dgettext("page-dataset-details", "See on data.gouv.fr") %>
                  </.link>
                </div>
                <div class="reuse__details">
                  <div>
                    <h3><%= reuse["title"] %></h3>
                    <p><%= MarkdownHandler.markdown_to_safe_html!(reuse["description"]) %></p>
                  </div>
                </div>
              </div>
            <% end %>
          </div>
        </section>
      <% end %>
    <% end %>
    """
  end

  def mount(
        _params,
        %{
          "dataset_datagouv_id" => dataset_datagouv_id,
          "locale" => locale
        },
        socket
      ) do
    socket =
      socket
      |> assign(:dataset_datagouv_id, dataset_datagouv_id)
      |> assign(:reuses, [])
      |> assign(:fetch_reuses_error, false)
      |> assign(:loading, true)

    Gettext.put_locale(locale)

    # async reuses loading
    send(self(), {:fetch_data_gouv_reuses, dataset_datagouv_id})

    {:ok, socket}
  end

  def handle_info({:fetch_data_gouv_reuses, dataset_datagouv_id}, socket) do
    # in case data.gouv api is down, datasets pages should still be available on our site
    %{reuses: reuses, fetch_reuses_error: fetch_reuses_error} =
      case Datagouvfr.Client.Reuses.Wrapper.get(%{datagouv_id: dataset_datagouv_id}) do
        {:ok, reuses} -> %{reuses: reuses, fetch_reuses_error: false}
        _ -> %{reuses: [], fetch_reuses_error: true}
      end

    Phoenix.PubSub.broadcast(
      TransportWeb.PubSub,
      "dataset_reuses_count:#{dataset_datagouv_id}",
      {:count, reuses |> length()}
    )

    socket =
      socket
      |> assign(:reuses, reuses)
      |> assign(:fetch_reuses_error, fetch_reuses_error)
      |> assign(:loading, false)

    {:noreply, socket}
  end
end

defmodule TransportWeb.CountReusesLive do
  use Phoenix.LiveView
  use Gettext, backend: TransportWeb.Gettext

  def render(assigns) do
    ~H"""
    <%= if assigns[:count] && @count > 0 do %>
      <div class="menu-item"><a href="#dataset-reuses"><%= dgettext("page-dataset-details", "Reuses") %></a></div>
    <% end %>
    """
  end

  def mount(_, %{"dataset_datagouv_id" => dataset_datagouv_id, "locale" => locale}, socket) do
    Gettext.put_locale(locale)

    if connected?(socket) do
      # messages are sent by TransportWeb.ReusesLive
      Phoenix.PubSub.subscribe(TransportWeb.PubSub, "dataset_reuses_count:#{dataset_datagouv_id}")
    end

    {:ok, socket}
  end

  def handle_info({:count, count}, socket) do
    socket = socket |> assign(:count, count)
    {:noreply, socket}
  end
end
