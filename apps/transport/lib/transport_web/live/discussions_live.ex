defmodule TransportWeb.DiscussionsLive do
  @moduledoc """
  Display data.gouv discussions on the dataset page
  """
  use Phoenix.LiveView
  import TransportWeb.Gettext

  def render(assigns) do
    ~H"""
    <script nonce={@nonce}>
      window.addEventListener('phx:discussions-loaded', (event) => {
        event.detail.ids.forEach(id =>
          addSeeMore(
            "0px",
            "#comments-discussion-" + id,
            "<%= dgettext("page-dataset-details", "Display more") %>",
            "<%= dgettext("page-dataset-details", "Display less") %>",
            "discussion"
          )
        )
        // Scroll to the right place after discussions have been loaded
        if (location.hash) location.href = location.hash;
      })
    </script>

    <%= if assigns[:discussions] do %>
      <div>
        <%= for discussion <- @discussions do %>
          <%= Phoenix.View.render(TransportWeb.DatasetView, "_discussion.html",
            discussion: discussion,
            current_user: @current_user,
            socket: @socket,
            dataset: @dataset,
            admin_member_ids: @admin_member_ids,
            org_member_ids: @org_member_ids,
            org_logo_thumbnail: @org_logo_thumbnail,
            locale: @locale
          ) %>
        <% end %>
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
          "locale" => locale,
          "csp_nonce_value" => nonce
        },
        socket
      ) do
    socket =
      socket
      |> assign(:current_user, current_user)
      |> assign(:dataset, dataset)
      |> assign(:locale, locale)
      |> assign(:nonce, nonce)

    Gettext.put_locale(locale)

    # async comments loading
    send(self(), {:fetch_data_gouv_discussions, dataset})

    {:ok, socket}
  end

  def handle_info({:fetch_data_gouv_discussions, %DB.Dataset{} = dataset}, socket) do
    discussions = Datagouvfr.Client.Discussions.Wrapper.get(dataset.datagouv_id)

    {org_member_ids, org_logo_thumbnail} = get_datagouv_org_infos(dataset)

    Phoenix.PubSub.broadcast(
      TransportWeb.PubSub,
      "dataset_discussions_count:#{dataset.datagouv_id}",
      {:count, discussions |> length()}
    )

    socket =
      socket
      |> assign(
        discussions: discussions,
        org_member_ids: org_member_ids,
        org_logo_thumbnail: org_logo_thumbnail,
        admin_member_ids: DB.Contact.admin_datagouv_ids()
      )
      |> push_event("discussions-loaded", %{
        ids: discussions |> Enum.filter(&discussion_should_be_closed?/1) |> Enum.map(& &1["id"])
      })

    {:noreply, socket}
  end

  @doc """
  Decides if a discussion coming from data.gouv.fr API should be displayed as closed for a less cluttered UI.

  A discussion is closed if:
  - it has a "closed" key with a value (same behaviour than on data.gouv.fr)
  - if the last comment inside the discussion is older than 2 months (because people often forget to close discussions)
  """
  def discussion_should_be_closed?(%{"closed" => closed}) when not is_nil(closed), do: true

  def discussion_should_be_closed?(%{"discussion" => comment_list}) do
    latest_comment_datetime =
      comment_list
      |> Enum.map(fn comment ->
        {:ok, comment_datetime, 0} = DateTime.from_iso8601(comment["posted_on"])
        comment_datetime
      end)
      |> Enum.max(DateTime)

    two_months_ago = DateTime.utc_now() |> TimeWrapper.shift(months: -2)
    DateTime.compare(two_months_ago, latest_comment_datetime) == :gt
  end

  defp get_datagouv_org_infos(%DB.Dataset{} = dataset) do
    case organization_info(dataset) do
      {:ok, %{"members" => members, "logo_thumbnail" => logo_thumbnail}} ->
        {Enum.map(members, fn member -> member["user"]["id"] end), logo_thumbnail}

      _ ->
        {[], nil}
    end
  end

  defp organization_info(%DB.Dataset{organization_id: organization_id}) when is_binary(organization_id) do
    Datagouvfr.Client.Organization.Wrapper.get(organization_id, restrict_fields: true)
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
