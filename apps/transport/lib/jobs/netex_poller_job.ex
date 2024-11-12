defmodule Transport.Jobs.NeTExPollerJob do
  @moduledoc """
  Companion module to the validator for NeTEx files, used to handle long
  standing validations.
  """
  use Oban.Worker, tags: ["validation"], max_attempts: 180, queue: :resource_validation

  alias Transport.Validators.NeTEx

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{
          "validation_id" => validation_id,
          "resource_history_id" => resource_history_id
        },
        attempt: attempt
      }) do
    NeTEx.poll_validation_results(validation_id, attempt)
    |> NeTEx.handle_validation_results(resource_history_id, fn ^validation_id -> snooze_poller(attempt) end)
  end

  def snooze_poller(attempt) do
    {:snooze, NeTEx.poll_interval(attempt)}
  end
end
