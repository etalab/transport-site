defmodule TransportWeb.Backoffice.DashboardController do
  use TransportWeb, :controller

  # alias DB.{Dataset, LogsImport, LogsValidation, Region, Repo, Resource}
  # import Ecto.Query
  require Logger

  def index(conn, _params) do
    conn
    |> render("index.html")
  end
end
