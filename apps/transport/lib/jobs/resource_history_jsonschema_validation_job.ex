defmodule Transport.Jobs.ResourceHistoryJSONSchemaValidationJob do
  @moduledoc """
  Validate a `DB.ResourceHistory` and stores the result in the database.
  """
  use Oban.Worker, max_attempts: 3, queue: :resource_validation, tags: ["validation"]
  import Ecto.Query
  alias Transport.Shared.Schemas.Wrapper, as: Schemas

  @doc """
  `perform/1` can:
  - Validate a single `DB.ResourceHistory` using the JSON Schema validator.
    Make sure the `DB.ResourceHistory` has a JSON Schema schema otherwise the
    validator will raise an error.
  - Enqueue validation jobs for all `DB.ResourceHistory` with a JSON Schema
    that have not been validated yet.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_history_id" => resource_history_id}}) when is_integer(resource_history_id) do
    resource_history = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)

    if resource_history |> DB.MultiValidation.already_validated?(validator()) do
      {:discard, "resource history #{resource_history_id} is already validated by #{validator_name()}"}
    else
      :ok = validator().validate_and_save(resource_history)
    end
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    validator_name = validator_name()
    json_schemas = "jsonschema" |> Schemas.schemas_by_type() |> Map.keys()

    DB.ResourceHistory.base_query()
    |> join(:left, [resource_history: rh], mv in DB.MultiValidation,
      on: mv.resource_history_id == rh.id and mv.validator == ^validator_name,
      as: :multi_validation
    )
    |> where([resource_history: _rh], fragment("payload ->>'schema_name'") in ^json_schemas)
    |> where([multi_validation: mv], is_nil(mv.id))
    |> select([resource_history: rh], rh.id)
    |> DB.Repo.all()
    |> Enum.each(fn resource_history_id ->
      %{resource_history_id: resource_history_id} |> __MODULE__.new() |> Oban.insert!()
    end)

    :ok
  end

  defp validator, do: Transport.Validators.EXJSONSchema
  defp validator_name, do: validator().validator_name()
end
