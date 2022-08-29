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
    field(:max_error, :string)

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

  def base_query, do: from(mv in DB.MultiValidation, as: :multi_validation)

  @spec join_resource_history_with_latest_validation(Ecto.Query.t(), binary() | [binary()]) :: Ecto.Query.t()
  @doc """
  joins the query with the latest validation, given a validator name or a list of validator names
  """
  def join_resource_history_with_latest_validation(query, validator) do
    latest_validation = multi_validation_subquery(validator)

    query
    |> join(:inner, [resource_history: rh], mv in DB.MultiValidation,
      on: mv.resource_history_id == rh.id,
      as: :multi_validation
    )
    |> join(:inner_lateral, [multi_validation: mv], latest in subquery(latest_validation), on: latest.id == mv.id)
  end

  defp multi_validation_subquery(v) do
    DB.MultiValidation
    |> where(
      [mv],
      mv.resource_history_id == parent_as(:resource_history).id
    )
    |> filter_on_validator(v)
    |> order_by([mv], desc: :inserted_at)
    |> select([mv], mv.id)
    |> limit(1)
  end

  defp filter_on_validator(query, validator_names) when is_list(validator_names) do
    query
    |> where([mv], mv.validator in ^validator_names)
  end

  defp filter_on_validator(query, validator_name) do
    query
    |> where([mv], mv.validator == ^validator_name)
  end

  @spec already_validated?(map(), module()) :: boolean()
  def already_validated?(%DB.ResourceHistory{id: id}, validator) do
    validator_name = validator.validator_name()

    DB.MultiValidation
    |> where([mv], mv.validator == ^validator_name and mv.resource_history_id == ^id)
    |> DB.Repo.exists?()
  end

  @spec resource_latest_validation(integer(), atom | nil) :: __MODULE__.t() | nil
  def resource_latest_validation(_, nil), do: nil

  def resource_latest_validation(resource_id, validator) when is_atom(validator) do
    validator_name = validator.validator_name()

    DB.MultiValidation
    |> join(:left, [mv], rh in DB.ResourceHistory,
      on: rh.id == mv.resource_history_id and rh.resource_id == ^resource_id
    )
    |> join(:left, [mv, rh], r in DB.Resource, on: r.id == mv.resource_id and r.id == ^resource_id)
    |> where([mv, rh, r], mv.validator == ^validator_name and (not is_nil(rh.id) or not is_nil(r.id)))
    |> order_by([mv, rh, r], desc: rh.inserted_at, desc: r.id, desc: mv.validation_timestamp)
    |> preload(:metadata)
    |> limit(1)
    |> DB.Repo.one()
  end

  @spec dataset_latest_validation(integer(), [module()]) :: map
  def dataset_latest_validation(dataset_id, validators) do
    validators_names = validators |> Enum.map(fn v -> v.validator_name() end)

    latest_validations =
      DB.MultiValidation
      |> distinct([mv], [mv.resource_history_id, mv.resource_id, mv.validator])
      |> order_by([mv],
        desc: mv.resource_history_id,
        desc: mv.resource_id,
        desc: mv.validator,
        desc: mv.validation_timestamp
      )
      |> where([mv], mv.validator in ^validators_names)

    latest_resource_history =
      DB.ResourceHistory
      |> distinct([rh], [rh.resource_id])
      |> order_by([rh], desc: rh.inserted_at)

    DB.Resource
    |> join(:left, [r], rh in subquery(latest_resource_history), on: rh.resource_id == r.id)
    |> join(:left, [r, rh], mv in subquery(latest_validations),
      on: rh.id == mv.resource_history_id or r.id == mv.resource_id
    )
    |> join(:left, [r, rh, mv], metadata in DB.ResourceMetadata, on: metadata.multi_validation_id == mv.id)
    |> where([r, rh, mv], r.dataset_id == ^dataset_id)
    |> select([r, rh, mv, metadata], {r.id, mv, metadata})
    |> DB.Repo.all()
    |> Enum.group_by(fn {k, _, _} -> k end, fn {_, mv, metadata} ->
      if is_nil(mv) do
        nil
      else
        # you cannot preload in a subquery, so we cannot preload the multi-validation associated metadata easily
        # we do the work manually, with a join and then put the metadata in the multi-validation
        Map.put(mv, :metadata, metadata)
      end
    end)
  end

  @doc """
  Get a metadata field, given a preloaded multi_validation struct. Returns nil if it fails.

  iex> get_metadata_info(%DB.MultiValidation{metadata: %DB.ResourceMetadata{metadata: %{age: 11}}}, :age)
  11
  iex> get_metadata_info(%DB.MultiValidation{metadata: %DB.ResourceMetadata{metadata: %{age: 11}}}, :foo)
  nil
  iex> get_metadata_info(nil, :foo)
  nil
  iex> get_metadata_info(nil, :foo, [])
  []
  """
  def get_metadata_info(multi_validation, metadata_key, default \\ nil)

  def get_metadata_info(%__MODULE__{metadata: %{metadata: metadata}}, metadata_key, default) do
    Map.get(metadata, metadata_key, default)
  end

  def get_metadata_info(_, _, default), do: default
end
