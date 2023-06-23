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

  @spec already_validated?(DB.ResourceHistory.t(), module()) :: boolean()
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
    |> preload([:metadata, :resource_history])
    |> limit(1)
    |> DB.Repo.one()
  end

  @spec resource_latest_validations(integer(), atom, DateTime.t()) :: [__MODULE__.t()]
  def resource_latest_validations(resource_id, validator, %DateTime{} = date_from) do
    validator_name = validator.validator_name()

    DB.MultiValidation
    |> where([mv], mv.validator == ^validator_name and mv.resource_id == ^resource_id and mv.inserted_at >= ^date_from)
    |> order_by([mv], asc: mv.validation_timestamp)
    |> DB.Repo.all()
  end

  @spec resource_history_latest_validation(integer(), atom | nil) :: __MODULE__.t() | nil
  def resource_history_latest_validation(_, nil), do: nil

  def resource_history_latest_validation(resource_history_id, validator) when is_atom(validator) do
    validator_name = validator.validator_name()

    DB.MultiValidation
    |> join(:inner, [mv], rh in DB.ResourceHistory,
      on: rh.id == mv.resource_history_id and rh.id == ^resource_history_id
    )
    |> where([mv, rh], mv.validator == ^validator_name)
    |> order_by([mv, _rh], desc: mv.validation_timestamp)
    |> preload(:metadata)
    |> limit(1)
    |> DB.Repo.one()
  end

  @spec dataset_latest_validation(integer(), [module()]) :: map
  def dataset_latest_validation(dataset_id, validators) do
    validators_names = validators |> Enum.map(fn v -> v.validator_name() end)

    resource_history_query =
      DB.ResourceHistory.base_query()
      |> where([resource_history: rh], parent_as(:resource).id == rh.resource_id)
      |> order_by([resource_history: rh], desc: rh.inserted_at)
      |> limit(1)

    multi_validation_query =
      DB.MultiValidation.base_query()
      |> where(
        [multi_validation: mv],
        parent_as(:resource).id == mv.resource_id or parent_as(:rh).id == mv.resource_history_id
      )
      |> where([multi_validation: mv], mv.validator in ^validators_names)
      |> order_by([multi_validation: mv], desc: mv.validation_timestamp)
      |> distinct([multi_validation: mv], [mv.resource_history_id, mv.resource_id, mv.validator])

    resource_metadata_query =
      DB.ResourceMetadata.base_query()
      |> where([metadata: rm], parent_as(:mv).id == rm.multi_validation_id)

    DB.Resource.base_query()
    |> join(:left_lateral, [], rh in subquery(resource_history_query), on: true, as: :rh)
    |> join(:left_lateral, [], mv in subquery(multi_validation_query), on: true, as: :mv)
    |> join(:left_lateral, [], rm in subquery(resource_metadata_query), on: true, as: :rm)
    |> where([resource: r], r.dataset_id == ^dataset_id)
    |> select([resource: r, mv: mv, rm: rm], {r.id, mv, rm})
    |> DB.Repo.all()
    |> Enum.group_by(fn {k, _, _} -> k end, fn {_, mv, metadata} ->
      if is_nil(mv) do
        nil
      else
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

  def get_metadata_info(%__MODULE__{metadata: %DB.ResourceMetadata{metadata: metadata}}, metadata_key, default) do
    Map.get(metadata, metadata_key, default)
  end

  def get_metadata_info(_, _, default), do: default

  @doc """
  Get modes from the metadata, given a preloaded multi_validation struct. Returns nil if it fails.

  iex> get_metadata_modes(%DB.MultiValidation{metadata: %DB.ResourceMetadata{modes: ["foo"]}}, :default)
  ["foo"]
  iex> get_metadata_modes(%DB.MultiValidation{metadata: nil}, :foo)
  :foo
  """
  def get_metadata_modes(multi_validation, default \\ nil)
  def get_metadata_modes(%__MODULE__{metadata: %DB.ResourceMetadata{modes: modes}}, _), do: modes
  def get_metadata_modes(_, default), do: default
end
