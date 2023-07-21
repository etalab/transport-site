defmodule TransportWeb.DiscussionsLive do
  @moduledoc """
  Display data.gouv discussions on the dataset page
  """
  use Phoenix.LiveView
  import TransportWeb.Gettext
  import TransportWeb.Endpoint

  def render(assigns) do

    ~H"""
          <script src={TransportWeb.Endpoint.static_path(@socket, "/js/utils.js")} />

      <script>
    window.addEventListener('phx:discussions-loaded', () => {
      console.log("yoooo");
    })
    </script>


    <%= if assigns[:discussions] do %>
      <div>


        <%= Phoenix.View.render(TransportWeb.DatasetView, "_discussions.html",
          discussions: @discussions,
          current_user: @current_user,
          socket: @socket,
          dataset: @dataset,
          locale: @locale
        ) %>
      </div>
    <% else %>
      <div>
        <%= dgettext("page-dataset-details", "loading discussions...") %>
      </div>
    <% end %>
    """
  end

  def mount(
        _params,
        %{
          "current_user" => current_user,
          "dataset" => dataset,
          "locale" => locale
        },
        socket
      ) do
    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:dataset, dataset)
      |> assign(:locale, locale)

    Gettext.put_locale(locale)

    # async comments loading
    send(self(), {:fetch_data_gouv_discussions, dataset.datagouv_id})

    {:ok, socket}
  end

  def handle_info({:fetch_data_gouv_discussions, dataset_datagouv_id}, socket) do
    discussions = Datagouvfr.Client.Discussions.Wrapper.get(dataset_datagouv_id)

    Phoenix.PubSub.broadcast(
      TransportWeb.PubSub,
      "dataset_discussions_count:#{dataset_datagouv_id}",
      {:count, discussions |> length()}
    )

    socket = socket |> assign(:discussions, discussions) |> push_event("discussions-loaded", %{})

    {:noreply, socket}
  end
end

defmodule TransportWeb.CountDiscussionsLive do
  @moduledoc """
  A live counter of dicussions for the dataset
  """
  use Phoenix.LiveView, container: {:span, []}

  def render(assigns) do
    ~H"""
    <%= if assigns[:count], do: "(#{@count})" %>
    """
  end

  def mount(_, %{"dataset_datagouv_id" => dataset_datagouv_id}, socket) do
    if connected?(socket) do
      # messages are sent by TransportWeb.DiscussionsLive
      Phoenix.PubSub.subscribe(TransportWeb.PubSub, "dataset_discussions_count:#{dataset_datagouv_id}")
    end

    {:ok, socket}
  end

  def handle_info({:count, count}, socket) do
    socket = socket |> assign(:count, count)
    {:noreply, socket}
  end
end
