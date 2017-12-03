defmodule TransportWeb.API.DatasetSerializer do
  @moduledoc """
  DatasetSerializer represents a Dataset resource, following the json-api spec.
  """

  use TransportWeb, :serializer
  alias BSON.ObjectId
  alias Transport.ReusableData.Dataset

  location "/datasets/:slug/"
  attributes [:title, :slug, :coordinates, :validations]

  def id(%Dataset{} = dataset, _) do
    ObjectId.encode!(dataset._id)
  end
end
