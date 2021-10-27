defmodule TransportWeb.Backoffice.ObanController do
  use TransportWeb, :controller

  require Logger

  def index(conn, %{"resource_id" => resource_id}) do
    {:ok, %{id: job_id}} =
      %{resource_id: resource_id}
      |> Oban.Job.new(queue: :default, worker: Transport.GeojsonConverterJob)
      |> Oban.insert()

    conn
    |> assign(:resource_id, resource_id)
    |> assign(:job_id, job_id)
    |> render("index.html")
  end
end
