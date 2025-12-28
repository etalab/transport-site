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
      end)
    else
      0
    end
  end

  def notification_count(%{count: _, static: _} = assigns) do
    ~H"""
    <% class = if @static, do: "notification_badge static", else: "notification_badge" %>
    <span
      :if={@count > 0}
      class={class}
      aria-label={dngettext("default", "%{count} notification count", "%{count} notifications count", @count)}
    >
      <%= @count %>
    </span>
    """
  end
end
