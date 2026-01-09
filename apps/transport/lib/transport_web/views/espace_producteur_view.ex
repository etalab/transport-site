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

  def show_important_information?(checks) do
    checks |> Map.values() |> Enum.any?(&Transport.DatasetChecks.has_issues?/1)
  end

  def important_information(%{} = assigns) do
    ~H"""
    <tr>
      <td>
        <a href={dataset_path(TransportWeb.Endpoint, :details, @dataset.slug)} target="_blank">
          <i class="fa fa-external-link"></i>
          {@dataset.custom_title}
        </a>
      </td>
      <.issue_title issue={@issue} check_name={@check_name} multi_validation={@multi_validation} locale={@locale} />
      <.issue_name issue={@issue} check_name={@check_name} multi_validation={@multi_validation} />
      <.issue_link mode={@mode} issue={@issue} check_name={@check_name} dataset={@dataset} />
    </tr>
    """
  end

  defp issue_title(%{issue: %DB.Resource{}, check_name: :expiring_resource} = assigns) do
    ~H"""
    <td>{@issue.title} <span class="label">{@issue.format}</span>
      <TransportWeb.DatasetView.validity_dates multi_validation={@multi_validation} locale={@locale} /></td>
    """
  end

  defp issue_title(%{issue: %DB.Resource{}} = assigns) do
    ~H"""
    <td>{@issue.title} <span class="label">{@issue.format}</span></td>
    """
  end

  defp issue_title(%{issue: _} = assigns) do
    ~H"""
    <td>{@issue["title"]}</td>
    """
  end

  defp issue_name(%{check_name: :expiring_resource, multi_validation: %DB.MultiValidation{} = mv} = assigns) do
    end_date = DB.MultiValidation.get_metadata_info(mv, "end_date") |> Date.from_iso8601!()

    if Date.compare(end_date, Date.utc_today()) in [:eq, :lt] do
      ~H"""
      <td>{dgettext("espace-producteurs", "Expired resource")}</td>
      """
    else
      ~H"""
      <td>{Transport.DatasetChecks.issue_name(@check_name)}</td>
      """
    end
  end

  defp issue_name(%{} = assigns) do
    ~H"""
    <td>{Transport.DatasetChecks.issue_name(@check_name)}</td>
    """
  end

  defp issue_link(%{mode: :producer, check_name: :unanswered_discussions} = assigns) do
    ~H"""
    <td>
      <a
        href={dataset_path(TransportWeb.Endpoint, :details, @dataset.slug) <> ~s|#discussion-#{@issue["id"]}|}
        class="button-outline primary small"
        data-tracking-category="espace_producteur"
        data-tracking-action="important_information_see_discussion_button"
      >
        <i class="icon fas fa-comments"></i>{dgettext("espace-producteurs", "See the discussion")}
      </a>
    </td>
    """
  end

  defp issue_link(%{mode: :producer, check_name: _} = assigns) do
    ~H"""
    <td>
      <a
        href={espace_producteur_path(TransportWeb.Endpoint, :edit_resource, @dataset.id, @issue.datagouv_id)}
        class="button-outline primary small"
        data-tracking-category="espace_producteur"
        data-tracking-action="important_information_edit_resource_button"
      >
        <i class="fa fa-edit"></i>{dgettext("espace-producteurs", "Edit resource")}
      </a>
    </td>
    """
  end

  defp issue_link(%{mode: :reuser, issue: %DB.Resource{}} = assigns) do
    ~H"""
    <td>
      <a
        href={resource_path(TransportWeb.Endpoint, :details, @issue.id)}
        class="button-outline primary small"
        target="_blank"
        data-tracking-category="espace_reutilisateur"
        data-tracking-action="important_information_see_resource_button"
      >
        {dgettext("reuser-space", "See the resource")}
      </a>
    </td>
    """
  end

  defp issue_link(%{mode: :reuser, check_name: :recent_discussions} = assigns) do
    ~H"""
    <td>
      <a
        href={dataset_path(TransportWeb.Endpoint, :details, @dataset.slug) <> ~s|#discussion-#{@issue["id"]}|}
        class="button-outline primary small"
        data-tracking-category="espace_producteur"
        data-tracking-action="important_information_see_discussion_button"
      >
        <i class="icon fas fa-comments"></i>{dgettext("espace-producteurs", "See the discussion")}
      </a>
    </td>
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
