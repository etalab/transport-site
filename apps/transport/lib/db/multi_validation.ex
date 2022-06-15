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

    DB.MultiValidation
    |> join(:inner, [mv], rh in DB.ResourceHistory,
      on: rh.id == mv.resource_history_id and rh.resource_id == ^resource_id
    )
    |> where([mv], mv.validator == ^validator_name)
    |> order_by([mv, rh], desc: rh.inserted_at, desc: mv.validation_timestamp)
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
      |> distinct([rh], [rh.resource_id])
      |> order_by([rh], desc: rh.inserted_at)

    DB.Resource
    |> join(:left, [r], rh in subquery(latest_resource_history), on: rh.resource_id == r.id)
    |> join(:left, [r, rh], mv in subquery(latest_validations), on: rh.id == mv.resource_history_id)
    |> where([r, rh, mv], r.dataset_id == ^dataset_id)
    |> select([r, rh, mv], {r.id, mv})
    |> DB.Repo.all()
    |> Enum.group_by(fn {k, _} -> k end, fn {_, v} -> v end)
  end
end
