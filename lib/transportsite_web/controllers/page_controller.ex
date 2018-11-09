defmodule TransportsiteWeb.PageController do
  use TransportsiteWeb, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
