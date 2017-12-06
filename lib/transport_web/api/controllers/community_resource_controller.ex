defmodule TransportWeb.API.CommunityResourceController do
  use TransportWeb, :controller
  alias Transport.ReusableData

  def index(%Plug.Conn{} = conn, %{"dataset_id" => dataset_id}) do
    render(
      conn,
      data: ReusableData.list_community_resources(conn, dataset_id)
    )
  end
end
