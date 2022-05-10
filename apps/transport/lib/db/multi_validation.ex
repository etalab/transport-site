defmodule DB.MultiValidation do
  @moduledoc """
  Validation model allowing multiple validations on the same data
  """
  use Ecto.Schema
  use TypedEctoSchema
  import Ecto.Query

  typed_schema "multi_validation" do
    field(:validation_timestamp, :utc_datetime_usec)
    field(:validator, :string)
    field(:transport_tools_version, :string)
    field(:command, :string)
    field(:result, :map)
    field(:data_vis, :map)

    belongs_to(:resource, DB.Resource)
    belongs_to(:resource_history, DB.ResourceHistory)
    field(:validated_data_name, :string)

    belongs_to(:secondary_resource, DB.Resource, foreign_key: :secondary_resource_id)
    belongs_to(:secondary_resource_history, DB.ResourceHistory, foreign_key: :secondary_resource_history_id)
    field(:secondary_validated_data_name, :string)

    has_one(:metadata, DB.ResourceMetadata)
    timestamps(type: :utc_datetime_usec)
  end

  @spec already_validated?(map(), module()) :: boolean()
  def already_validated?(%DB.ResourceHistory{id: id}, validator) do
    validator_name = validator.validator_name()

    DB.MultiValidation
    |> where([mv], mv.validator == ^validator_name and mv.resource_history_id == ^id)
    |> DB.Repo.exists?()
  end

  @spec resource_latest_validation(integer(), atom) :: __MODULE__.t() | nil
  def resource_latest_validation(resource_id, validator) do
    validator_name = validator.validator_name()

    # when resource and resource_history are linked by the resource id,
    # the join with resource will be removed in this query.
    DB.MultiValidation
    |> join(:left, [mv], rh in DB.ResourceHistory, on: rh.id == mv.resource_history_id)
    |> join(:left, [mv, rh], r in DB.Resource, on: r.datagouv_id == rh.datagouv_id)
    |> where([mv, rh, r], mv.validator == ^validator_name and r.id == ^resource_id)
    |> order_by([mv, rh, r], desc: mv.validation_timestamp, desc: rh.inserted_at)
    |> preload(:metadata)
    |> limit(1)
    |> DB.Repo.one()
  end
end
