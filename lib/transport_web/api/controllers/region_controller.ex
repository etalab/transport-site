defmodule TransportWeb.API.RegionController do
  use TransportWeb, :controller

  def index(%Plug.Conn{} = conn, _params) do
    render(
      conn, %{data: []}
     # data: Mongo.find(
     #   :mongo,
     #   "regions",
     #   %{},
     #   pool: DBConnection.Poolboy
     # ) |> Enum.to_list
    )
  end

end
