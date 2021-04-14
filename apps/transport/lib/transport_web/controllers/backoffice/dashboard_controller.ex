defmodule TransportWeb.Backoffice.DashboardController do
  use TransportWeb, :controller

  # alias DB.{Dataset, LogsImport, LogsValidation, Region, Repo, Resource}
  # import Ecto.Query
  require Logger

  @dashboard_import_count_sql File.read!("lib/queries/dashboard_import_count.sql")

  def index(conn, _params) do
    conn
    |> render("index.html")
  end
end
