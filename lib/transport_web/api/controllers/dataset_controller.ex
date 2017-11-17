defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData

  def index(conn, _params) do
    render(conn, "index.jsonapi", data: ReusableData.list_datasets)
  end
end
