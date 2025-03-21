defmodule TransportWeb.Live.FollowedDatasetsLive do
  @moduledoc """
  Display followed datasets on the reuser space.
  """
  use Phoenix.LiveView
  use TransportWeb.InputHelpers
  import Ecto.Query
  import TransportWeb.DatasetView, only: [icon_type_path: 1]
  use Gettext, backend: TransportWeb.Gettext
  import TransportWeb.InputHelpers
  import TransportWeb.Router.Helpers

  @impl true
  def render(assigns) do
    ~H"""
    <div class="pb-24">
      <.form :let={f} for={%{}} phx-change="change" class="search-followed-datasets">
        <%= search_input(f, :search, value: @search) %>
        <%= if Enum.count(@select_options) > 1 do %>
          <%= select(f, :type, [{dgettext("reuser-space", "All"), ""}] ++ @select_options,
            selected: @type,
            label: dgettext("reuser-space", "Data type")
          ) %>
        <% end %>
      </.form>
    </div>
    <div :if={Enum.empty?(@filtered_datasets)} class="notification">
      <%= dgettext("reuser-space", "No results") %>
    </div>
    <div :if={not Enum.empty?(@filtered_datasets)} class="row">
      <%= for dataset <- Enum.sort_by(@filtered_datasets, & &1.custom_title) do %>
        <div class="panel dataset__panel">
          <div class="panel__content">
            <div class="dataset__description">
              <div class="dataset__image">
                <%= img_tag(DB.Dataset.logo(dataset), alt: dataset.custom_title) %>
              </div>
              <div class="dataset__infos">
                <h3 class="dataset__title">
                  <a href={dataset_path(@socket, :details, dataset.slug)} target="_blank">
                    <i class="fa fa-external-link-alt" aria-hidden="true"></i>
                    <%= dataset.custom_title %>
                  </a>
                </h3>
                <div class="dataset-localization">
                  <i class="icon fa fa-map-marker-alt" /><%= DB.Dataset.get_territory_or_nil(dataset) %>
                </div>
              </div>
            </div>
            <div :if={not is_nil(icon_type_path(dataset))} class="dataset__type">
              <%= img_tag(icon_type_path(dataset), alt: dataset.type) %>
            </div>
          </div>
          <div class="panel__extra">
            <div class="dataset__info">
              <div class="shortlist__notices">
                <dl class="dataset-format shortlist__notice">
                  <%= unless dataset |> DB.Dataset.formats() |> Enum.empty?() do %>
                    <dt class="shortlist__label"><%= dgettext("page-shortlist", "Format") %></dt>
                    <%= for format <- DB.Dataset.formats(dataset) do %>
                      <dd class="label"><%= format %></dd>
                    <% end %>
                  <% end %>
                </dl>
              </div>
            </div>
          </div>
          <div class="panel__extra">
            <a href={reuser_space_path(@socket, :datasets_edit, dataset.id)} class="no-bg">
              <button class="button-outline primary small"><%= dgettext("reuser-space", "Manage") %></button>
            </a>
          </div>
        </div>
      <% end %>
    </div>
    <script type="text/javascript" src={static_path(@socket, "/js/app.js")} />
    <script nonce={@nonce}>
      [form] = document.getElementsByClassName("search-followed-datasets");
      form.onkeydown = function(event) {
        if (event.key === "Enter") return false;
      }
    </script>
    """
  end

  @impl true
  def mount(
        _params,
        %{"dataset_ids" => dataset_ids, "locale" => locale, "csp_nonce_value" => nonce},
        %Phoenix.LiveView.Socket{} = socket
      ) do
    Gettext.put_locale(locale)

    datasets =
      DB.Dataset.base_query()
      |> preload([:region, :aom, :communes, :resources])
      |> where([dataset: d], d.id in ^dataset_ids)
      |> DB.Repo.all()

    socket =
      assign(socket, %{
        nonce: nonce,
        datasets: datasets,
        filtered_datasets: datasets,
        select_options: select_options(datasets),
        search: "",
        type: ""
      })

    {:ok, socket}
  end

  defp select_options(datasets) do
    datasets
    |> Enum.map(fn %DB.Dataset{type: type} -> type end)
    |> Enum.uniq()
    |> Enum.map(fn type -> {DB.Dataset.type_to_str(type), type} end)
    |> Enum.sort_by(fn {friendly_type, _} -> friendly_type end)
  end

  @impl true
  def handle_event("change", params, %Phoenix.LiveView.Socket{} = socket) do
    {:noreply, filter_datasets(socket, params)}
  end

  def filter_datasets(
        %Phoenix.LiveView.Socket{assigns: %{datasets: datasets}} = socket,
        %{"search" => search} = params
      ) do
    type = Map.get(params, "type", "")
    filtered_datasets = datasets |> filter_by_type(type) |> filter_by_search(search)

    socket |> assign(%{filtered_datasets: filtered_datasets, search: search, type: type})
  end

  defp filter_by_type(datasets, ""), do: datasets

  defp filter_by_type(datasets, value),
    do: Enum.filter(datasets, fn %DB.Dataset{type: type} -> type == value end)

  defp filter_by_search(datasets, ""), do: datasets

  defp filter_by_search(datasets, value) do
    Enum.filter(datasets, fn %DB.Dataset{custom_title: custom_title} ->
      String.contains?(normalize(custom_title), normalize(value))
    end)
  end

  @doc """
  iex> normalize("Paris")
  "paris"
  iex> normalize("vélo")
  "velo"
  iex> normalize("Châteauroux")
  "chateauroux"
  """
  def normalize(value) do
    value |> String.normalize(:nfd) |> String.replace(~r/[^A-z]/u, "") |> String.downcase()
  end
end
