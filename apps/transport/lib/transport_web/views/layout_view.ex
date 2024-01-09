defmodule TransportWeb.LayoutView do
  use TransportWeb, :view
  alias __MODULE__
  alias Phoenix.Controller
  import TransportWeb.DatasetView, only: [markdown_to_safe_html!: 1]

  def current_path(conn) do
    Controller.current_path(conn)
  end

  def has_flash(%Plug.Conn{} = conn), do: not Enum.empty?(conn.assigns.flash)

  def add_locale_to_url(conn, locale) do
    query_params = conn.query_params |> Map.put("locale", locale) |> Plug.Conn.Query.encode()
    "#{conn.request_path}?#{query_params}"
  end
end
