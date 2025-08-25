defmodule DB.ProxyRequest do
  @moduledoc """
  Represents a HTTP request made to the proxy.
  """
  use Ecto.Schema
  use TypedEctoSchema

  @primary_key false

  typed_schema "proxy_request" do
    field(:time, :utc_datetime_usec)
    field(:proxy_id, :string)
    belongs_to(:token, DB.Token)
  end
end
