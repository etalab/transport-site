defmodule Transport.Jobs.ResourceHistoryTableSchemaValidationJob do
  @moduledoc """
  Validate a `DB.ResourceHistory` and stores the result in the database.
  """
  use Oban.Worker, max_attempts: 3, queue: :resource_validation, tags: ["validation"]
  alias Transport.Jobs.ResourceHistorySchemaValidation

  @doc """
  `perform/1` can:
  - Validate a single `DB.ResourceHistory` using the Table Schema validator.
    Make sure the `DB.ResourceHistory` has a Table Schema schema otherwise the
    validator will raise an error.
  - Enqueue validation jobs for all `DB.ResourceHistory` with a Table Schema
    that have not been validated yet.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_history_id" => resource_history_id}}) when is_integer(resource_history_id) do
    ResourceHistorySchemaValidation.validate_resource_history_for_schema(resource_history_id, validator())
  end

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    ResourceHistorySchemaValidation.enqueue_jobs_for_schema_type("tableschema", __MODULE__, validator())
  end

  def validator, do: Transport.Validators.TableSchema
end
