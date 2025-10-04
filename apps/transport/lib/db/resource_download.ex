defmodule DB.ResourceDownload do
  @moduledoc """
  Represents a resource download.
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  @primary_key false

  typed_schema "resource_download" do
    field(:time, :utc_datetime_usec)
    belongs_to(:token, DB.Token)
    belongs_to(:resource, DB.Resource)
  end

  def delete_all_for_resource(%DB.Resource{id: resource_id}) do
    DB.ResourceDownload
    |> where(resource_id: ^resource_id)
    |> DB.Repo.delete_all()
  end
end
