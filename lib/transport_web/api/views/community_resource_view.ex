defmodule TransportWeb.API.CommunityResourceView do
  alias TransportWeb.API.CommunityResourceSerializer

  def render(_conn, %{data: data}) do
    JaSerializer.format(CommunityResourceSerializer, data)
  end
end
