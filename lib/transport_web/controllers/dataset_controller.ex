defmodule TransportWeb.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData

  def index(conn, _) do
    conn
    |> assign(:datasets, ReusableData.list_datasets)
    |> render("index.html")
  end

  def details(conn, %{"slug" => slug}) do
    slug
    |> ReusableData.get_dataset()
    |> case do
      nil    -> render conn, "error.html"
      dataset -> conn
                 |> assign(:dataset, dataset)
                 |> render("details.html")
    end
  end
end
