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

  def show_important_information?(checks), do: show_important_information?(checks, :producer, [])

  def show_important_information?(checks, :producer, _hidden_alerts) do
    checks |> Map.values() |> Enum.any?(&Transport.DatasetChecks.has_issues?/1)
  end

  def show_important_information?(checks, :reuser, hidden_alerts) do
    Enum.any?(checks, &has_visible_issues?(&1, hidden_alerts))
  end

  defp has_visible_issues?({dataset_id, dataset_checks}, hidden_alerts) do
    Enum.any?(dataset_checks, &has_visible_issue?(&1, dataset_id, hidden_alerts))
  end

  defp has_visible_issue?({check_name, issues}, dataset_id, hidden_alerts) do
    Enum.any?(issues, fn issue ->
      issue = extract_issue(issue)
      not issue_hidden?(hidden_alerts, %{id: dataset_id}, check_name, issue)
    end)
  end

  defp extract_issue(%DB.Resource{} = resource), do: resource
  defp extract_issue({%DB.Resource{} = resource, [_mv | _]}), do: resource
  defp extract_issue(discussion), do: discussion

  def issue_hidden?(hidden_alerts, dataset, check_name, issue) do
    resource_id = if is_struct(issue, DB.Resource), do: issue.id, else: nil
    discussion_id = if is_map(issue) and Map.has_key?(issue, "id"), do: issue["id"], else: nil

    DB.HiddenReuserAlert.hidden?(hidden_alerts, dataset.id, check_name,
      resource_id: resource_id,
      discussion_id: discussion_id
    )
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
      <.issue_link mode={@mode} issue={@issue} check_name={@check_name} dataset={@dataset} conn={@conn} />
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
      <div class="action-buttons">
        <a
          href={resource_path(TransportWeb.Endpoint, :details, @issue.id)}
          class="button-outline primary small"
          target="_blank"
          data-tracking-category="espace_reutilisateur"
          data-tracking-action="important_information_see_resource_button"
        >
          {dgettext("reuser-space", "See the resource")}
        </a>
        <.hide_button dataset={@dataset} check_name={@check_name} resource_id={@issue.id} conn={@conn} />
      </div>
    </td>
    """
  end

  defp issue_link(%{mode: :reuser, check_name: :recent_discussions} = assigns) do
    ~H"""
    <td>
      <div class="action-buttons">
        <a
          href={dataset_path(TransportWeb.Endpoint, :details, @dataset.slug) <> ~s|#discussion-#{@issue["id"]}|}
          class="button-outline primary small"
          data-tracking-category="espace_producteur"
          data-tracking-action="important_information_see_discussion_button"
        >
          <i class="icon fas fa-comments"></i>{dgettext("espace-producteurs", "See the discussion")}
        </a>
        <.hide_button dataset={@dataset} check_name={@check_name} discussion_id={@issue["id"]} conn={@conn} />
      </div>
    </td>
    """
  end

  defp hide_button(%{} = assigns) do
    assigns = assigns |> Map.put_new(:resource_id, nil) |> Map.put_new(:discussion_id, nil)

    ~H"""
    <.form :let={f} for={%{}} action={reuser_space_path(@conn, :hide_alert, @dataset.id)} class="hide-alert-form">
      {hidden_input(f, :check_type, value: @check_name)}
      {hidden_input(f, :resource_id, value: @resource_id)}
      {hidden_input(f, :discussion_id, value: @discussion_id)}
      <button
        type="submit"
        class="button-outline secondary small"
        title={dgettext("reuser-space", "Hide for 7 days")}
        data-tracking-category="espace_reutilisateur"
        data-tracking-action="important_information_hide_alert_button"
      >
        <i class="fa fa-eye-slash"></i>
      </button>
    </.form>
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
