defmodule TransportWeb.EditDatasetLive do
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
      for={@form_params}
      as={:form}
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

      <p :if={not is_nil(@dataset) and not @dataset.is_active} class="notification warning">
        Ce jeu de données a été supprimé de data.gouv.fr. Il faudrait probablement remplacer son URL source ou le déréférencer.
      </p>

      <div class="pt-24">
        <%= InputHelpers.text_input(f, :url,
          placeholder: dgettext("backoffice", "Dataset's url"),
          value: @form_params["url"].value
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
          value: @form_params["custom_title"].value
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

      <p :if={not is_nil(@dataset) and @dataset.is_hidden} class="notification">
        Ce jeu de données est masqué
      </p>

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
            <%= dgettext("backoffice", "Company SIREN code") %>
            <%= InputHelpers.text_input(f, :legal_owner_company_siren,
              placeholder: "821611431",
              pattern: "\\d{9,9}",
              value: @form_params["legal_owner_company_siren"].value
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
          <%= checkbox(f, :national_dataset, value: @form_params["national_dataset"].value) %><%= dgettext(
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
                value: @form_params["associated_territory_name"].value
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
            <%= InputHelpers.submit(dgettext("backoffice", "Save")) %>
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
      |> assign(:form_params, form_params(dataset))

    {:ok, socket}
  end

  def form_params(%DB.Dataset{} = dataset) do
    %{
      "url" => Dataset.datagouv_url(dataset),
      "custom_title" => dataset.custom_title,
      "legal_owner_company_siren" => dataset.legal_owner_company_siren,
      "national_dataset" => dataset.region_id == 14,
      "associated_territory_name" => dataset.associated_territory_name
    }
    |> to_form()
  end

  def form_params(nil) do
    %{
      "url" => "",
      "custom_title" => "",
      "legal_owner_company_siren" => "",
      "national_dataset" => "",
      "associated_territory_name" => ""
    }
    |> to_form()
  end

  def get_legal_owners(%Dataset{} = dataset) do
    # current legal owners, to initiate the state of the legal_owner_select_live component
    %{legal_owners_aom: legal_owners_aom, legal_owners_region: legal_owners_region} = dataset

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
      "Opérateur de transport",
      "Partenariat régional",
      "Fournisseur de système",
      "Autre"
    ]

  def handle_event(
        "change_dataset",
        %{"_target" => ["form", "url"], "form" => %{"url" => datagouv_url} = form_params},
        socket
      ) do
    # new dataset or existing dataset with new url => get info from data.gouv
    socket =
      if datagouv_url != "" and
           (socket.assigns.dataset == nil or
              datagouv_url != Dataset.datagouv_url(socket.assigns.dataset)) do
        Task.async(fn -> get_datagouv_infos(datagouv_url) end)
        socket
      else
        assign(socket, datagouv_infos: nil, dataset_organization: nil)
      end

    socket = socket |> assign(:form_params, form_params |> to_form())
    {:noreply, socket}
  end

  def handle_event("change_dataset", %{"_target" => _, "form" => %{} = form_params}, socket) do
    # persist the form input values
    socket = socket |> assign(:form_params, form_params |> to_form())
    {:noreply, socket}
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
