defmodule TransportWeb.EditDatasetLive do
  use Phoenix.LiveView
  use Phoenix.HTML
  import TransportWeb.Gettext, only: [dgettext: 2]
  alias DB.Dataset
  import TransportWeb.Router.Helpers
  alias TransportWeb.InputHelpers
  import Ecto.Query

  def render(assigns) do
    ~H"""
    <.form
      :let={f}
      for={:form}
      action={@form_url}
      phx-change="change_dataset"
      phx-submit="save"
      phx-trigger-action={@trigger_submit}
      onkeydown="return event.key != 'Enter';"
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

          <div class="pt-12 pb-12">
            <%= if is_nil(dataset_datagouv_id) do %>
              Impossible de trouver ce jeu de données sur data.gouv
            <% else %>
              <div>Jeu de données <strong>"<%= @datagouv_infos[:datagouv_title] %>"</strong></div>
              <div class="pt-12">
                Son identifiant data.gouv est <code><%= @datagouv_infos[:dataset_datagouv_id] %></code>
              </div>
              <div class="pt-12">
                <%= if @datagouv_infos[:dataset_id] do %>
                  ⚠️ Ce jeu de données est déjà référencé <%= link("sur le PAN",
                    to: backoffice_page_path(@socket, :edit, @datagouv_infos[:dataset_id]),
                    target: "_blank"
                  ) %>, il n'est pas possible de le référencer une seconde fois.
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

      <%= live_render(@socket, TransportWeb.CustomTagsLive,
        id: "custom_tags",
        session: %{"dataset" => @dataset, "form" => f}
      ) %>

      <div :if={@dataset_organization} class="panel mt-48">
        <div class="panel-explanation">
          <%= dgettext("backoffice", "published by") %>
        </div>
        <h4><%= @dataset_organization %></h4>
        <%= select(f, :organization_type, @organization_types,
          selected:
            if not is_nil(@dataset) do
              @dataset.organization_type
            else
              ""
            end,
          prompt: dgettext("backoffice", "Publisher type")
        ) %>
      </div>

      <div class="panel mt-48">
        <div class="panel-explanation">
          <%= dgettext("backoffice", "Legal owners") %>
        </div>
        <.live_component module={TransportWeb.LegalOwnerSelectLive} id="owners_selection" form={f} owners={@legal_owners} />
        <div class="pt-12"><%= dgettext("backoffice", "or") %></div>
        <div class="pt-12">
          <label>
            <%= dgettext("backoffice", "company SIREN code") %>
            <%= InputHelpers.text_input(f, :legal_owner_company_siren,
              placeholder: "exemple : 821611431",
              pattern: "\\d{9,9}",
              value:
                if not is_nil(@dataset) do
                  @dataset.legal_owner_company_siren
                else
                  ""
                end
            ) %>
          </label>
        </div>
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
          <%= select(f, :region_id, @regions,
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
            <%= live_render(@socket, TransportWeb.Live.CommuneField,
              id: "commune_field",
              session: %{"insee" => "", "form" => f}
            ) %>
          <% else %>
            <%= live_render(@socket, TransportWeb.Live.CommuneField,
              id: "commune_field",
              session: %{"insee" => @dataset.aom.insee_commune_principale, "form" => f}
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
      <div id="backoffice_dataset_submit_buttons" class={if is_nil(@dataset), do: "pb-48"}>
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
          "regions" => regions
        },
        socket
      ) do
    form_url =
      case dataset do
        nil -> backoffice_dataset_path(socket, :post)
        %{id: dataset_id} -> backoffice_dataset_path(socket, :post, dataset_id)
      end

    dataset_organization =
      case dataset do
        nil -> nil
        %{organization: organization} -> organization
      end

    socket =
      socket
      |> assign(:dataset, dataset)
      |> assign(:dataset_types, dataset_types)
      |> assign(:regions, regions)
      |> assign(:form_url, form_url)
      |> assign(:dataset_organization, dataset_organization)
      |> assign(:organization_types, organization_types())
      |> assign(:legal_owners, get_legal_owners(dataset))
      |> assign(:trigger_submit, false)

    {:ok, socket}
  end

  def get_legal_owners(%Dataset{id: dataset_id}) do
    # current legal owners, to initiate the state of the legal_owner_select_live component
    %{legal_owners_aom: legal_owners_aom, legal_owners_region: legal_owners_region} =
      DB.Dataset |> preload([:legal_owners_aom, :legal_owners_region]) |> DB.Repo.get(dataset_id)

    legal_owners_aom = legal_owners_aom |> Enum.map(fn aom -> %{id: aom.id, type: "aom", label: aom.nom} end)

    legal_owners_region =
      legal_owners_region |> Enum.map(fn region -> %{id: region.id, type: "region", label: region.nom} end)

    legal_owners_aom ++ legal_owners_region
  end

  def get_legal_owners(_), do: []

  def organization_types,
    do: [
      "AOM",
      "Réseau",
      "Fournisseur de système",
      "Opérateur de transport",
      "Syndicat Mixte",
      "Autre"
    ]

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
      {:noreply, assign(socket, datagouv_infos: nil, dataset_organization: nil)}
    end
  end

  # allow a classic http form submit when the form is submitted by user
  def handle_event("save", _, socket) do
    {:noreply, assign(socket, trigger_submit: true)}
  end

  def handle_event(_, _, socket) do
    {:noreply, socket}
  end

  # handle info sent from the child live component to update the list of legal owners
  def handle_info({:updated_legal_owner, legal_owners}, socket) do
    {:noreply, socket |> assign(:legal_owners, legal_owners)}
  end

  # get the result from the async Task triggered by "change_dataset"
  def handle_info({ref, datagouv_infos}, socket) do
    # we stop monitoring the process after receiving the result
    Process.demonitor(ref, [:flush])

    socket =
      socket
      |> assign(datagouv_infos: datagouv_infos)
      |> assign(dataset_organization: Map.get(datagouv_infos, :organization))

    {:noreply, socket}
  end

  def handle_info(_, socket) do
    {:noreply, socket}
  end

  def get_datagouv_infos(datagouv_url) do
    infos = Datagouvfr.Client.Datasets.get_infos_from_url(datagouv_url)

    case infos do
      nil ->
        %{dataset_datagouv_id: nil}

      %{id: dataset_datagouv_id, title: title, organization: organization} ->
        # does the dataset already exists?
        dataset_id =
          case DB.Dataset |> DB.Repo.get_by(datagouv_id: dataset_datagouv_id) do
            %{id: id} -> id
            _ -> nil
          end

        %{
          dataset_datagouv_id: dataset_datagouv_id,
          datagouv_title: title,
          dataset_id: dataset_id,
          organization: organization
        }
    end
  end
end
