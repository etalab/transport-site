defmodule TransportWeb.DiscussionsLive do
  @moduledoc """
  Display data.gouv discussions on the dataset page
  """
  use Phoenix.LiveView
  import TransportWeb.Gettext

  def render(assigns) do
    ~H"""
    <script>
      window.addEventListener('phx:discussions-loaded', (event) => {
        event.detail.ids.forEach(id =>
          addSeeMore(
            "0px",
            "#comments-discussion-" + id,
            "<%= dgettext("page-dataset-details", "Display more") %>",
            "<%= dgettext("page-dataset-details", "Display less") %>"
          )
        )
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

    socket =
      socket
      |> assign(:discussions, discussions)
      |> push_event("discussions-loaded", %{
        ids: discussions |> Enum.filter(&discussion_should_be_closed?/1) |> Enum.map(& &1["id"])
      })

    {:noreply, socket}
  end

  @doc """
    Decides if a discussion coming from data.gouv.fr API should be dislayed as closed for a less cluttered UI
    A discussion is closed if it has a "closed" key with a value (same behaviour than on data.gouv.fr)
    or if the last comment inside the discussion is older than 2 months (because people often forget to close discussions)
  """
  def discussion_should_be_closed?(%{"closed" => closed}) when not is_nil(closed), do: true

  def discussion_should_be_closed?(%{"discussion" => comment_list}) do
    {:ok, latest_comment_datetime, 0} = List.first(comment_list)["posted_on"] |> DateTime.from_iso8601()
    DateTime.utc_now() |> Timex.shift(months: -2) |> DateTime.compare(latest_comment_datetime) == :gt
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
