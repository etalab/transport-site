defmodule TransportWeb.EditDatasetLive do
  # In Phoenix v1.6+ apps, the line below should be: use MyAppWeb, :live_view
  use Phoenix.LiveView
  use Phoenix.HTML
  import TransportWeb.Gettext, only: [dgettext: 2]
  alias DB.Dataset
  import TransportWeb.Router.Helpers
  alias TransportWeb.InputHelpers

  def render(assigns) do
    ~H"""
    <.form
      :let={f}
      for={:form}
      action={@form_url}
      phx-change="change_dataset"
      phx-submit="save"
      phx-trigger-action={@trigger_submit}
    >
      <h1>
        <%= if is_nil(@dataset) do %>
          <%= dgettext("backoffice", "Add a dataset") %>
        <% else %>
          <%= dgettext("backoffice", "Edit a dataset") %>
        <% end %>
      </h1>
      <%= unless is_nil(assigns[:dataset]) do %>
        <div class="pb-24">
          <i class="fa fa-external-link-alt"></i>
          <%= link(dgettext("backoffice", "See dataset on website"), to: dataset_path(@socket, :details, @dataset.id)) %>
        </div>
      <% end %>

      <div class="pt-24">
        <%= InputHelpers.text_input(f, :url,
          placeholder: dgettext("backoffice", "Dataset's url"),
          value:
            if not is_nil(@dataset) do
              Dataset.datagouv_url(@dataset)
            else
              ""
            end
        ) %>

        <%= if assigns[:datagouv_infos] do %>
          <% dataset_datagouv_id = @datagouv_infos[:dataset_datagouv_id] %>

          <div class="pt-12">
            <%= if is_nil(dataset_datagouv_id) do %>
              Impossible de trouver ce jeu de données sur data.gouv
            <% else %>
              <div>Jeu de données <strong>"<%= @datagouv_infos[:datagouv_title] %>"</strong></div>
              Son identifiant data.gouv est <strong><%= @datagouv_infos[:dataset_datagouv_id] %></strong>
              <div class="pt-12 pb-12">
                <%= if @datagouv_infos[:dataset_id] do %>
                  ⚠️ Ce jeu de données est déjà référencé chez nous, il n'est pas possible de le référencer une seconde fois. <%= @datagouv_infos[
                    :dataset_id
                  ] %>
                <% else %>
                  Ce jeu n'est pas encore référencé chez nous ✅
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= InputHelpers.text_input(f, :custom_title,
          placeholder: dgettext("backoffice", "name"),
          value:
            if not is_nil(@dataset) do
              @dataset.custom_title
            else
              ""
            end
        ) %>
        <%= InputHelpers.select(f, :type, @dataset_types,
          selected:
            if not is_nil(@dataset) do
              @dataset.type
            else
              "public-transit"
            end
        ) %>
      </div>

      <div class="panel mt-48">
        <div class="panel__header">
          <h4>
            <%= dgettext("backoffice", "Associated territory") %>
          </h4>
          <%= dgettext("backoffice", "Choose one") %>
        </div>
        <div class="panel__content">
          <%= checkbox(f, :national_dataset, value: not is_nil(@dataset) && @dataset.region_id == 14) %><%= dgettext(
            "backoffice",
            "National dataset"
          ) %>
        </div>
        <p class="separator">
          - <%= dgettext("resource", "or") %> -
        </p>
        <div class="panel__content">
          <%= dgettext("backoffice", "Dataset linked to a region") %>
          <%= select(f, :region_id, Enum.map(@regions, &{&1.nom, &1.id}),
            selected:
              if not is_nil(@dataset) do
                @dataset.region_id
              else
                ""
              end,
            prompt: "Pas un jeu de données régional"
          ) %>
        </div>
        <p class="separator">
          - <%= dgettext("resource", "or") %> -
        </p>
        <%= dgettext("backoffice", "Dataset linked to an AOM") %>
        <div class="panel__content">
          <%= if is_nil(@dataset) || is_nil(@dataset.aom) || is_nil(@dataset.aom.insee_commune_principale) do %>
            <%= live_render(@socket, TransportWeb.Live.CommuneField, id: "commune_field", session: %{"insee" => ""}) %>
          <% else %>
            <%= live_render(@socket, TransportWeb.Live.CommuneField,
              id: "commune_field",
              session: %{"insee" => @dataset.aom.insee_commune_principale}
            ) %>
          <% end %>
        </div>
        <p class="separator">
          - <%= dgettext("resource", "or") %> -
        </p>
        <div class="panel__content">
          <%= dgettext("backoffice", "Dataset linked to a list of cities in data.gouv.fr") %>
          <div>
            <div class="pt-12">
              <%= InputHelpers.text_input(f, :associated_territory_name,
                placeholder: dgettext("backoffice", "Name of the associtated territory (used in the title of the dataset)"),
                value:
                  if not is_nil(@dataset) do
                    @dataset.associated_territory_name
                  else
                    ""
                  end
              ) %>
            </div>
          </div>
        </div>
      </div>
      <div class="backoffice_dataset_submit_buttons">
        <div>
          <%= if is_nil(@dataset) do %>
            <%= hidden_input(f, :action, value: "new") %>
            <%= InputHelpers.submit(dgettext("backoffice", "Add")) %>
          <% else %>
            <%= hidden_input(f, :action, value: "edit") %>
            <%= InputHelpers.submit(dgettext("backoffice", "Edit")) %>
          <% end %>
        </div>
        <div>
          <%= link(dgettext("backoffice", "Cancel"), to: backoffice_page_path(@socket, :index)) %>
        </div>
      </div>
    </.form>
    """
  end

  def mount(
        _params,
        %{
          "dataset" => dataset,
          "dataset_types" => dataset_types,
          "regions" => regions,
          "form_url" => form_url
        },
        socket
      ) do
    socket =
      socket
      |> assign(:dataset, dataset)
      |> assign(:dataset_types, dataset_types)
      |> assign(:regions, regions)
      |> assign(:form_url, form_url)
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def handle_event(
        "change_dataset",
        %{"_target" => ["form", "url"], "form" => %{"url" => datagouv_url}},
        socket
      ) do
    # new dataset or existing dataset with new url => get info from data.gouv
    if datagouv_url != "" and
         (socket.assigns.dataset == nil or
            datagouv_url != Dataset.datagouv_url(socket.assigns.dataset)) do
      Task.async(fn -> get_datagouv_infos(datagouv_url) end)
      {:noreply, socket}
    else
      {:noreply, assign(socket, datagouv_infos: nil)}
    end
  end

  def handle_event("save", _, socket) do
    {:noreply, assign(socket, trigger_submit: true)}
  end

  def handle_event(_, _, socket) do
    {:noreply, socket}
  end

  def handle_info({ref, datagouv_infos}, socket) do
    Process.demonitor(ref, [:flush])
    {:noreply, assign(socket, datagouv_infos: datagouv_infos)}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def get_datagouv_infos(datagouv_url) do
    case Datagouvfr.Client.Datasets.get_infos_from_url(datagouv_url) do
      nil ->
        %{dataset_datagouv_id: nil}

      [id: dataset_datagouv_id, title: title] ->
        # does the dataset already exists?
        dataset_id =
          case DB.Dataset |> DB.Repo.get_by(datagouv_id: dataset_datagouv_id) do
            %{id: id} -> id
            _ -> nil
          end

        %{dataset_datagouv_id: dataset_datagouv_id, datagouv_title: title, dataset_id: dataset_id}
    end
  end
end
