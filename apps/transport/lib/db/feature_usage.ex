defmodule DB.FeatureUsage do
  @moduledoc """
  Logs when a feature has been used by a contact with metadata.
  """
  use Ecto.Schema
  use TypedEctoSchema

  @primary_key false

  typed_schema "feature_usage" do
    field(:time, :utc_datetime_usec)

    field(:feature, Ecto.Enum,
      values: [
        :on_demand_validation,
        :download_resource_history,
        :post_discussion,
        :post_comment,
        :gtfs_diff,
        :autocomplete,
        :upload_file,
        :delete_resource,
        :upload_logo
      ]
    )

    field(:metadata, :map)
    belongs_to(:contact, DB.Contact)
  end

  def insert!(feature, contact_id, metadata) do
    %__MODULE__{}
    |> Ecto.Changeset.change(%{
      feature: feature,
      contact_id: contact_id,
      metadata: metadata,
      time: DateTime.utc_now()
    })
    |> DB.Repo.insert!()
  end
end
