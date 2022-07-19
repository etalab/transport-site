defmodule Transport.Jobs.ResourceHistorySchemaValidation do
  @moduledoc """
  A module to share common methods used to identify `DB.ResourceHistory` with
  a schema and validate them against a schema.

  It deals with JSON Schema and Table Schema.
  """
  import Ecto.Query
  alias Transport.Shared.Schemas.Wrapper, as: Schemas

  def validate_resource_history_for_schema(resource_history_id, validator) do
    resource_history = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)

    if resource_history |> DB.MultiValidation.already_validated?(validator) do
      {:discard, "resource history #{resource_history_id} is already validated by #{validator.validator_name()}"}
    else
      :ok = validator.validate_and_save(resource_history)
    end
  end

  def enqueue_jobs_for_schema_type(schema_type, validation_job_module, validator)
      when schema_type in ["tableschema", "jsonschema"] do
    validator_name = validator.validator_name()
    schemas = schema_type |> Schemas.schemas_by_type() |> Map.keys()

    DB.ResourceHistory.base_query()
    |> join(:left, [resource_history: rh], mv in DB.MultiValidation,
      on: mv.resource_history_id == rh.id and mv.validator == ^validator_name,
      as: :multi_validation
    )
    |> where([resource_history: _rh], fragment("payload ->>'schema_name'") in ^schemas)
    |> where([multi_validation: mv], is_nil(mv.id))
    |> select([resource_history: rh], rh.id)
    |> DB.Repo.all()
    |> Enum.each(fn resource_history_id ->
      %{resource_history_id: resource_history_id} |> validation_job_module.new() |> Oban.insert!()
    end)
  end
end
