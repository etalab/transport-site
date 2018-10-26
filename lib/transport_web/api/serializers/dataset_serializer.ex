defmodule TransportWeb.API.DatasetSerializer do
  @moduledoc """
  DatasetSerializer represents a Dataset resource, following the json-api spec.
  """

  use TransportWeb, :serializer

  location "/datasets/:slug/"
  attributes [:title, :slug, :id, :validations]

end
