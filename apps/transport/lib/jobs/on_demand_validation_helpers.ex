defmodule Transport.Jobs.OnDemandValidationHelpers do
  @moduledoc """
  Shared code for jobs implementing the On Demand validation.
  """
  import Ecto.Changeset
  import Ecto.Query

  def terminal_state(result), do: {:terminal, result}
  def delegated_state, do: :delegated
  def snoozed_state(duration_in_seconds), do: {:snooze, duration_in_seconds}

  def completed, do: %{"state" => "completed"}

  def error(error_message), do: %{"state" => "error", "error_reason" => error_message}

  def handle_validation_result(result, multivalidation_id) do
    case result do
      {:terminal, changes} -> update_multivalidation(multivalidation_id, changes)
      :delegated -> :ok
      {:snooze, _duration_in_seconds} -> result
    end
  end

  defp update_multivalidation(multivalidation_id, changes) do
    validation = %{oban_args: oban_args} = DB.MultiValidation |> preload(:metadata) |> DB.Repo.get!(multivalidation_id)

    # update oban_args with validator output
    oban_args = Map.merge(oban_args, Map.get(changes, :oban_args, %{}))
    changes = changes |> Map.put(:oban_args, oban_args)

    {metadata, changes} = Map.pop(changes, :metadata)
    {features, changes} = Map.pop(changes, :features)

    validation
    |> change(changes)
    |> put_assoc(:metadata, %{metadata: metadata, features: features})
    |> DB.Repo.update!()

    :ok
  end
end
