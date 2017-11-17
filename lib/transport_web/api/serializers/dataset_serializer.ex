defmodule TransportWeb.API.DatasetSerializer do
  use TransportWeb, :serializer
  alias Transport.ReusableData.Dataset

  location "/datasets/:slug/"
  attributes [:slug, :coordinates]

  def id(%Dataset{} = dataset, _) do
    BSON.ObjectId.encode!(dataset._id)
  end
end
