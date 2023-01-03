defmodule TransportWeb.Backoffice.DashboardController do
  use TransportWeb, :controller
  require Logger

  @dashboard_import_count_sql File.read!("lib/queries/dashboard_import_count.sql")

  def index(conn, _params) do
    data =
      @dashboard_import_count_sql
      |> DB.Repo.query!()

    import_count_by_dataset_and_by_day =
      data.rows
      |> Enum.group_by(
        fn [dataset_id, _, _, _] -> dataset_id end,
        fn [_, date, import_count, success_count] -> {date, import_count, success_count} end
      )
      |> Enum.sort_by(fn {key, _value} -> key end)

    conn
    |> render("index.html", import_count_by_dataset_and_by_day: import_count_by_dataset_and_by_day)
  end
end
