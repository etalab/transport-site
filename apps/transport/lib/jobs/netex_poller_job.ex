defmodule Transport.Jobs.NeTExPollerJob do
  @moduledoc """
  Companion module to the validator for NeTEx files, used to handle long
  standing validations.
  """

  # Max attempts doesn't really matter here as it's useful for workers failing.
  # Here we mostly poll and excepted network errors, the worker won't fail.
  @max_attempts 3

  use Oban.Worker,
    tags: ["validation"],
    max_attempts: @max_attempts,
    queue: :resource_validation,
    unique: [fields: [:args, :worker]]

  alias Transport.Validators.NeTEx

  # Override the backoff to play nice and avoiding falling in very slow retry
  # after an important streak of snoozing (which increments the `attempt`
  # counter).
  #
  # See https://hexdocs.pm/oban/Oban.Worker.html#module-snoozing-jobs.
  @impl Worker
  def backoff(%Oban.Job{} = job) do
    corrected_attempt = @max_attempts - (job.max_attempts - job.attempt)

    Worker.backoff(%{job | attempt: corrected_attempt})
  end

  @impl Worker
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
