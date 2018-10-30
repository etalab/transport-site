defmodule TransportWeb.API.AOMController do
  use TransportWeb, :controller

  def index(%Plug.Conn{} = conn, _params) do
    #data = :mongo
    #|> Mongo.find("aoms", %{}, limit: 1, pool: DBConnection.Poolboy)
    #|> Enum.map(&(&1["properties"]))
    #|> Enum.to_list

    render(conn)
  end
end
