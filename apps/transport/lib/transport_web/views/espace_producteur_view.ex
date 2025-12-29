defmodule TransportWeb.EspaceProducteurView do
  use TransportWeb, :view
  use Phoenix.Component
  import TransportWeb.BreadCrumbs, only: [breadcrumbs: 1]

  @spec action_path(Plug.Conn.t()) :: any
  def action_path(%Plug.Conn{params: %{"resource_datagouv_id" => r_id}, assigns: %{dataset: dataset}} = conn),
    do: espace_producteur_path(conn, :post_file, dataset.datagouv_id, r_id)

  def action_path(%Plug.Conn{assigns: %{dataset: dataset}} = conn),
    do: espace_producteur_path(conn, :post_file, dataset.datagouv_id)

  def title(%Plug.Conn{params: %{"resource_datagouv_id" => _}}),
    do: dgettext("resource", "Resource modification")

  def title(_), do: dgettext("resource", "Add a new resource")

  def remote?(%{"filetype" => "remote"}), do: true
  def remote?(_), do: false

  @spec show_proxy_stats_block?([DB.Dataset.t()]) :: boolean()
  def show_proxy_stats_block?(datasets) do
    datasets |> Enum.flat_map(& &1.resources) |> Enum.any?(&DB.Resource.served_by_proxy?/1)
  end

  @spec show_downloads_stats?(DB.Dataset.t() | [DB.Dataset.t()]) :: boolean()
  def show_downloads_stats?(datasets) when is_list(datasets), do: Enum.any?(datasets, &show_downloads_stats?/1)

  def show_downloads_stats?(%DB.Dataset{resources: resources}) do
    Enum.any?(resources, &DB.Resource.hosted_on_datagouv?/1)
  end

  def show_urgent_issues?(checks) do
    checks |> Map.values() |> Enum.any?(&Transport.DatasetChecks.has_issues?/1)
  end

  def issue_title(%{issue: %DB.Resource{}} = assigns) do
    ~H"""
    <%= @issue.title %> <span class="label"><%= @issue.format %></span>
    """
  end

  def issue_title(%{issue: _} = assigns) do
    ~H"""
    <%= @issue["title"] %>
    """
  end

  def dataset_creation_url,
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("/fr/admin/dataset/new/")

  def datagouv_resource_edit_url(dataset_id, resource_id),
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("admin/datasets/#{dataset_id}/files?resource_id=#{resource_id}")

  def datagouv_resource_creation_url(dataset_id),
    do:
      :transport
      |> Application.fetch_env!(:datagouvfr_site)
      |> Path.join("/admin/datasets/#{dataset_id}/files")
end
