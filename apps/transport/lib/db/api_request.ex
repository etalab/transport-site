defmodule DB.APIRequest do
  @moduledoc """
  Represents a HTTP request made to the API.
  """
  use Ecto.Schema
  use TypedEctoSchema

  @primary_key false

  typed_schema "api_request" do
    field(:time, :utc_datetime_usec)
    field(:method, :string)
    field(:path, :string)
    belongs_to(:token, DB.Token)
  end
end
