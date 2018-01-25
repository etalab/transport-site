defmodule TransportWeb.API.ErrorSerializer do
  @moduledoc """
  ErrorSerializer represents an validation error, following the json-api spec.
  """

  use TransportWeb, :serializer
  alias Transport.ReusableData.Dataset

  location "/datasets/:slug/validations/"
  attributes [:errors, :warnings, :notices]
end
