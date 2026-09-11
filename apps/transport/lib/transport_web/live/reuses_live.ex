defmodule TransportWeb.ReusesLive do
  @moduledoc """
  Display data.gouv reuses on the dataset page
  """
  use Phoenix.LiveView
  use Gettext, backend: TransportWeb.Gettext
  alias TransportWeb.MarkdownHandler

  def render(assigns) do
    ~H"""
    <section class="white pt-48" id="dataset-reuses">
      <h2>{dgettext("page-dataset-details", "Reuses")}</h2>
      <%= cond do %>
        <% @loading -> %>
          <p>{dgettext("page-dataset-details", "Loading reuses…")}</p>
        <% @fetch_reuses_error -> %>
          <div class="panel reuses_not_available">
            🔌 {dgettext("page-dataset-details", "Reuses are temporarily unavailable")}
          </div>
        <% @reuses != [] -> %>
          <p>
            {dgettext(
              "page-dataset-details",
              "You will find below reuses created by individuals or organizations based on this dataset."
            )}
          </p>
          <div class="reuses">
            <.reuse :for={reuse <- @reuses} reuse={reuse} />
          </div>
        <% true -> %>
          <p>{dgettext("page-dataset-details", "No known reuse on this dataset.")}</p>
      <% end %>
    </section>
    """
  end

  defp reuse(%{reuse: _} = assigns) do
    ~H"""
    <div class="panel reuse">
      <img src={@reuse["image"]} alt={@reuse["title"]} />
      <div class="reuse__owner">{Phoenix.HTML.raw(owner(@reuse))}</div>
      <div class="reuse__links">
        <.link href={@reuse["url"]}>{dgettext("page-dataset-details", "Website")}</.link>
        <.link href={@reuse["page"]} target="_blank">
          {dgettext("page-dataset-details", "See on data.gouv.fr")}
        </.link>
      </div>
      <div class="reuse__details">
        <h3>{@reuse["title"]}</h3>
        {MarkdownHandler.markdown_to_safe_html!(@reuse["description"], &shift_headings/1)}
      </div>
    </div>
    """
  end

  # Shift headings to fit inside a reuse card (titled with <h3>).
  # h1→h4, h2→h5, h3→h6 so they don't clash with the page heading hierarchy.
  defp shift_headings(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.traverse_and_update(&shift_headings_tag/1)
    |> Floki.raw_html()
  end

  defp shift_headings_tag({tag, attrs, children}) do
    tag =
      case tag do
        "h1" -> "h4"
        "h2" -> "h5"
        "h3" -> "h6"
        "h4" -> "h6"
        "h5" -> "h6"
        "h6" -> "h6"
        unaltered -> unaltered
      end

    {tag, attrs, children}
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

  def owner(%{"organization" => %{"name" => name}}), do: ~s|<i class="fa fa-building icon"></i>| <> name
  def owner(%{"owner" => %{"name" => name}}), do: ~s|<i class="fa fa-user icon"></i>| <> name

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
    <div class="menu-item">
      <a href="#dataset-reuses">
        {dgettext("page-dataset-details", "Reuses")}
        <%= if assigns[:count] && @count > 0 do %>
          ({@count})
        <% end %>
      </a>
    </div>
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
