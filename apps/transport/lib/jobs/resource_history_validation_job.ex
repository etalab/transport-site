defmodule Transport.Jobs.ResourceHistoryValidationJob do
  @moduledoc """
  Validate a resource history and stores result in DB
  """
  use Oban.Worker, max_attempts: 3, tags: ["validation"]
  import Ecto.Query

  # validate all resource history with one validator
  @impl Oban.Worker
  def perform(%{args: %{"format" => format, "validator" => validator}}) do
    validator = String.to_existing_atom(validator)
    validator_name = validator.validator_name()

    DB.ResourceHistory
    |> join(:left, [rh], mv in DB.MultiValidation,
      on: rh.id == mv.resource_history_id and mv.validator == ^validator_name
    )
    |> where([rh, mv], fragment("payload->>'format' = ?", ^format) and is_nil(mv.id))
    |> select([rh], rh.id)
    |> limit(5)
    |> DB.Repo.all()
    |> Enum.each(fn id ->
      Transport.Jobs.ResourceHistoryValidationJob.new(%{resource_history_id: id, validator: validator}) |> Oban.insert()
    end)

    :ok
  end

  # validate one resource history with one validator
  @impl Oban.Worker
  def perform(%{args: %{"resource_history_id" => resource_history_id, "validator" => validator}})
      when is_integer(resource_history_id) do
    validator = String.to_existing_atom(validator)
    resource_history = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)

    unless resource_history |> DB.MultiValidation.already_validated?(validator) do
      validator.validate(resource_history)
    end

    :ok
  end

  @impl Oban.Worker
  def perform(%{args: %{"resource_history_id" => resource_history_id}}) when is_integer(resource_history_id) do
    %{payload: %{"format" => format}} = resource_history = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)

    format
    |> Transport.ValidatorsSelection.validators()
    |> Enum.reject(fn validator -> resource_history |> DB.MultiValidation.already_validated?(validator) end)
    |> Enum.each(fn validator -> validator.validate(resource_history) end)

    :ok
  end

  # validate all resource history with all validators
  @impl Oban.Worker
  def perform(%{}) do
    Transport.ValidatorsSelection.formats_and_validators()
    |> Enum.flat_map(fn {format, validators} -> Enum.zip(Stream.cycle([format]), validators) end)
    |> Enum.each(fn {format, validator} ->
      Transport.Jobs.ResourceHistoryValidationJob.new(%{format: format, validator: validator}) |> Oban.insert()
    end)

    :ok
  end
end
