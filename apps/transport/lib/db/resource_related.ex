defmodule DB.ResourceRelated do
  @moduledoc """
  A module to deal with `DB.Resource` related to other `DB.Resource`
  """
  use TypedEctoSchema

  @primary_key false
  typed_schema "resource_related" do
    belongs_to(:resource_src, DB.Resource, foreign_key: :resource_src_id, references: :id)
    belongs_to(:resource_dst, DB.Resource, foreign_key: :resource_dst_id, references: :id)
    field(:reason, Ecto.Enum, values: [:gtfs_rt_gtfs])
  end
end
