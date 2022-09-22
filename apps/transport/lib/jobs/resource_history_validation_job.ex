defmodule Transport.Jobs.ResourceHistoryValidationJob do
  @moduledoc """
  Validate a resource history and stores result in DB
  """
  use Oban.Worker, max_attempts: 3, queue: :resource_validation, tags: ["validation"]

  # wait for https://github.com/sorentwo/oban/issues/704 response
  # unique: [period: 5 * 60]

  import Ecto.Query

  @doc """
  Launch validation(s) on resource history.
  Depending on the arguments given, can launch one validation or many.
  It is handy to group validations per validator, to easily check which resource history
  are already validated.
  """
  # select all resource history with given format
  # validate them with one validator
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"format" => format, "validator" => validator} = args}) do
    force_validation = args |> Map.get("force_validation", false)
    only_latest_resource_history = args |> Map.get("only_latest_resource_history", false)

    validator = String.to_existing_atom(validator)
    validator_name = validator.validator_name()

    filter_force_validation = fn query ->
      case force_validation do
        true ->
          query |> where([rh, mv], fragment("payload->>'format' = ?", ^format))

        false ->
          query |> where([rh, mv], fragment("payload->>'format' = ?", ^format) and is_nil(mv.id))
      end
    end

    filter_only_latest_resource_history = fn query ->
      case only_latest_resource_history do
        true -> query |> distinct([rh], rh.resource_id)
        false -> query
      end
    end

    DB.ResourceHistory
    |> join(:left, [rh], mv in DB.MultiValidation,
      on: rh.id == mv.resource_history_id and mv.validator == ^validator_name
    )
    |> filter_force_validation.()
    |> filter_only_latest_resource_history.()
    |> order_by([rh], desc: rh.inserted_at)
    |> select([rh], rh.id)
    |> DB.Repo.all()
    |> Enum.each(fn id ->
      %{resource_history_id: id, validator: validator, force_validation: force_validation}
      |> Transport.Jobs.ResourceHistoryValidationJob.new()
      |> Oban.insert!()
    end)

    :ok
  end

  # validate one resource history with one validator
  @impl Oban.Worker
  def perform(%Oban.Job{
        args:
          %{"resource_history_id" => resource_history_id, "validator" => validator_string} = args
      })
      when is_integer(resource_history_id) do
    force_validation = args |> Map.get("force_validation", false)
    validator = String.to_existing_atom(validator_string)
    resource_history = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)

    case DB.MultiValidation.resource_history_latest_validation(resource_history.id, validator) do
      nil ->
        :ok = validator.validate_and_save(resource_history)
        :ok

      latest_validation ->
        if force_validation do
          :ok = validator.validate_and_save(resource_history)
          # delete previous validation, corresponding resource metadata is automatically deleted
          DB.Repo.delete(latest_validation)
          :ok
        else
          {:discard,
           "resource history #{resource_history_id} is already validated by #{validator_string}"}
        end
    end
  end

  # validate one resource history with all validators
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"resource_history_id" => resource_history_id}})
      when is_integer(resource_history_id) do
    resource_history = DB.ResourceHistory |> DB.Repo.get!(resource_history_id)

    resource_history
    |> Transport.ValidatorsSelection.validators()
    |> Enum.reject(fn validator ->
      resource_history |> DB.MultiValidation.already_validated?(validator)
    end)
    |> Enum.each(fn validator -> validator.validate_and_save(resource_history) end)

    :ok
  end
end
