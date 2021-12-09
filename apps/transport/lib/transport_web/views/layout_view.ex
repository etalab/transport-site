defmodule TransportWeb.LayoutView do
  use TransportWeb, :view
  alias __MODULE__
  alias Phoenix.Controller

  def current_path(conn) do
    Controller.current_path(conn)
  end

  def has_flash(conn) do
    # it's not nice to depend on some internal state, but it does not seems to have a better way
    # to check if the `put_flash` function has been called, and it's important for error pages
    not is_nil(conn.private[:phoenix_flash])
  end

  def add_locale_to_url(conn, locale) do
    query_params = conn.query_params |> Map.put("locale", locale) |> Plug.Conn.Query.encode()
    "#{conn.request_path}?#{query_params}"
  end
end
