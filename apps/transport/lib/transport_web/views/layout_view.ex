defmodule TransportWeb.LayoutView do
  use TransportWeb, :view
  use Phoenix.Component
  alias __MODULE__
  alias Phoenix.Controller
  import TransportWeb.DatasetView, only: [markdown_to_safe_html!: 1]

  def current_path(conn) do
    Controller.current_path(conn)
  end

  def has_flash(%Plug.Conn{} = conn), do: not Enum.empty?(conn.assigns.flash)

  @doc """
  The current user's avatar URL.
  If the logged-in user has a custom avatar, use its URL.
  Otherwise use the data.gouv.fr pixels for this user.
  """
  def avatar_url(%Plug.Conn{assigns: %{current_user: %{"avatar_thumbnail" => avatar_thumbnail}}})
      when is_binary(avatar_thumbnail) do
    avatar_thumbnail
  end

  def avatar_url(%Plug.Conn{assigns: %{current_user: %{"id" => datagouv_id}}}) do
    # https://doc.data.gouv.fr/api/reference/#/avatars/avatars
    "https://www.data.gouv.fr/api/1/avatars/#{datagouv_id}/50"
  end

  def avatar_url(%Plug.Conn{}), do: nil

  def add_locale_to_url(conn, locale) do
    query_params = conn.query_params |> Map.put("locale", locale) |> Plug.Conn.Query.encode()
    "#{conn.request_path}?#{query_params}"
  end

  def notifications_count(%Plug.Conn{} = conn) do
    if TransportWeb.Session.producer?(conn) do
      Enum.reduce(conn.assigns.datasets_checks, 0, fn check, acc ->
        Transport.DatasetChecks.count_issues(check) + acc
      end) + reuser_notifications_count(conn)
    else
      reuser_notifications_count(conn)
    end
  end

  def producer_notifications_count(%Plug.Conn{} = conn) do
    if TransportWeb.Session.producer?(conn) do
      Enum.reduce(conn.assigns.datasets_checks, 0, fn check, acc ->
        Transport.DatasetChecks.count_issues(check) + acc
      end)
    else
      0
    end
  end

  def reuser_notifications_count(%Plug.Conn{} = conn) do
    hidden_alerts = conn.assigns.hidden_reuser_alerts
    datasets = conn.assigns.followed_datasets
    checks = conn.assigns.followed_datasets_checks

    datasets
    |> Enum.zip(checks)
    |> Enum.reduce(0, fn {dataset, check}, acc ->
      count_visible_issues(check, dataset.id, hidden_alerts) + acc
    end)
  end

  defp count_visible_issues(check, dataset_id, hidden_alerts) do
    Enum.reduce(check, 0, fn {check_name, issues}, acc ->
      visible_count =
        Enum.count(issues, fn issue ->
          not DB.HiddenReuserAlert.hidden?(hidden_alerts, dataset_id, check_name, issue_opts(issue))
        end)

      visible_count + acc
    end)
  end

  defp issue_opts(%DB.Resource{id: resource_id}), do: [resource_id: resource_id]
  defp issue_opts({%DB.Resource{id: resource_id}, _}), do: [resource_id: resource_id]
  defp issue_opts(%{"id" => discussion_id}), do: [discussion_id: discussion_id]
  defp issue_opts(_), do: []

  def notification_count(%{count: _, static: _} = assigns) do
    ~H"""
    <% class = if @static, do: "notification_badge static", else: "notification_badge" %>
    <span
      :if={@count > 0}
      class={class}
      aria-label={dngettext("default", "%{count} notification count", "%{count} notifications count", @count)}
    >
      {@count}
    </span>
    """
  end
end
