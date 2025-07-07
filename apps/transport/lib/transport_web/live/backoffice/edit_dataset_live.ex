defmodule TransportWeb.EditDatasetLive do
  use Phoenix.LiveView
  use Phoenix.HTML
  use Gettext, backend: TransportWeb.Gettext
  alias DB.Dataset
  import TransportWeb.Router.Helpers
  alias TransportWeb.InputHelpers

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
      # TODO: see if we can avoid this
      |> assign(:new_covered_area, get_new_covered_area(dataset))
      |> assign(:trigger_submit, false)
      |> assign(:form_params, form_params(dataset))
      |> assign(:custom_tags, get_custom_tags(dataset))
      |> assign(:matches, [])

    {:ok, socket}
  end

  def form_params(%DB.Dataset{} = dataset) do
    insee = if is_nil(dataset.aom), do: "", else: dataset.aom.insee_commune_principale

    %{
      "url" => Dataset.datagouv_url(dataset),
      "custom_title" => dataset.custom_title,
      "legal_owner_company_siren" => dataset.legal_owner_company_siren,
      "national_dataset" => dataset.region_id == 14,
      "insee" => insee,
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
      "insee" => "",
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

  def get_new_covered_area(%Dataset{} = dataset) do
    # current covered area, to initiate the state of the new_covered_area_select_live component
    dataset
    |> DB.DatasetNewCoveredArea.preload_covered_area_objects()
    |> Map.get(:new_covered_areas)
  end

  def get_new_covered_area(_), do: []

  def get_custom_tags(%Dataset{} = dataset) do
    dataset.custom_tags || []
  end

  def get_custom_tags(_), do: []

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

  def handle_event("suggest_communes", %{"value" => query}, socket) when byte_size(query) <= 100 do
    # When taking out this legacy field, don’t forget to delete parts of the SearchCommunes module
    matches =
      query
      |> Transport.SearchCommunes.search()
      |> Enum.take(5)

    {:noreply, assign(socket, matches: matches)}
  end

  def handle_event(_, _, socket) do
    {:noreply, socket}
  end

  # handle info sent from the child live component to update the list of legal owners
  def handle_info({:updated_legal_owner, legal_owners}, socket) do
    {:noreply, socket |> assign(:legal_owners, legal_owners)}
  end

  def handle_info({:updated_custom_tags, custom_tags}, socket) do
    {:noreply, socket |> assign(:custom_tags, custom_tags)}
  end

  def handle_info({:updated_new_covered_area, new_covered_area}, socket) do
    {:noreply, socket |> assign(:new_covered_area, new_covered_area)}
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
