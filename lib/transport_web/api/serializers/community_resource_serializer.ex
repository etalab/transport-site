defmodule TransportWeb.API.CommunityResourceSerializer do
  @moduledoc """
  CommunityResourceSerializer represents a dataset modification, following the
  json-api spec.
  """

  use TransportWeb, :serializer
  alias Transport.ReusableData.CommunityResource

  location "/datasets/:id/community_resources/"

  attributes [
    :title,
    :description,
    :url,
    :organization_name,
    :organization_logo_thumbnail
  ]

  def organization_name(%CommunityResource{} = resource, _) do
    resource.organization.name
  end

  def organization_logo_thumbnail(%CommunityResource{} = resource, _) do
    resource.organization.logo_thumbnail
  end
end
