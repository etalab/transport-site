defmodule DB.ResourceDownload do
  @moduledoc """
  Represents a resource download.
  """
  use Ecto.Schema
  use TypedEctoSchema

  @primary_key false

  typed_schema "resource_download" do
    field(:time, :utc_datetime_usec)
    belongs_to(:token, DB.Token)
    belongs_to(:resource, DB.Resource)
  end
end
