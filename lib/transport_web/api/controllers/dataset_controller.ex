defmodule TransportWeb.API.DatasetController do
  use TransportWeb, :controller
  alias Transport.ReusableData

  def index(%Plug.Conn{} = conn, _params) do
    render(conn, data: ReusableData.list_datasets)
  end

  def show(%Plug.Conn{} = conn, %{"slug" => slug}) do
    render(conn, data: ReusableData.get_dataset(slug))
  end
end
