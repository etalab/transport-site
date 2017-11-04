defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData

  def index(conn, _) do
    conn
    |> assign(:datasets, ReusableData.list_datasets)
    |> render("index.html")
  end
end
