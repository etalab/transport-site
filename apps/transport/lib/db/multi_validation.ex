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
    field(:validator_version, :string)
    field(:command, :string)
    field(:result, :map)
    field(:data_vis, :map)

    # if the validation is enqueued via Oban, this field contains the job arguments
    # and its status (waiting, completed, etc)
    field(:oban_args, :map)

    belongs_to(:resource, DB.Resource)
    belongs_to(:resource_history, DB.ResourceHistory)
    field(:validated_data_name, :string)

    belongs_to(:secondary_resource, DB.Resource, foreign_key: :secondary_resource_id)
    belongs_to(:secondary_resource_history, DB.ResourceHistory, foreign_key: :secondary_resource_history_id)
    field(:secondary_validated_data_name, :string)

    has_one(:metadata, DB.ResourceMetadata)
    timestamps(type: :utc_datetime_usec)
  end

  def join_resource_history_with_latest_validation(query, validator) do
    latest_validation =
      DB.MultiValidation
      |> where(
        [mv],
        mv.resource_history_id == parent_as(:resource_history).id and mv.validator == ^validator
      )
      |> order_by([mv], desc: :inserted_at)
      |> select([mv], mv.id)
      |> limit(1)

    query
    |> join(:inner, [resource_history: rh], mv in DB.MultiValidation,
      on: mv.resource_history_id == rh.id,
      as: :multi_validation
    )
    |> join(:inner_lateral, [multi_validation: mv], latest in subquery(latest_validation), on: latest.id == mv.id)
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
    |> order_by([mv, rh, r], desc: rh.inserted_at, desc: mv.validation_timestamp)
    |> preload(:metadata)
    |> limit(1)
    |> DB.Repo.one()
  end

  @spec dataset_latest_validation(integer(), [module()]) :: map
  def dataset_latest_validation(dataset_id, validators) do
    validators_names = validators |> Enum.map(fn v -> v.validator_name() end)

    latest_validations =
      DB.MultiValidation
      |> distinct([mv], [mv.resource_history_id, mv.validator])
      |> order_by([mv], desc: mv.resource_history_id, desc: mv.validator, desc: mv.validation_timestamp)
      |> where([mv], mv.validator in ^validators_names)

    latest_resource_history =
      DB.ResourceHistory
      |> distinct([rh], [rh.datagouv_id])
      |> order_by([rh], desc: rh.inserted_at)

    DB.Resource
    |> join(:left, [r], rh in subquery(latest_resource_history), on: rh.datagouv_id == r.datagouv_id)
    |> join(:left, [r, rh], mv in subquery(latest_validations), on: rh.id == mv.resource_history_id)
    |> where([r, rh, mv], r.dataset_id == ^dataset_id)
    |> select([r, rh, mv], {r.id, mv})
    |> DB.Repo.all()
    |> Enum.group_by(fn {k, _} -> k end, fn {_, v} -> v end)
  end
end
