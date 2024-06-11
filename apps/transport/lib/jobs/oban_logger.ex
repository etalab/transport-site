defmodule Transport.Jobs.ObanLogger do
  @moduledoc """
  Logs the Oban job exceptions as warnings
  """
  require Logger
  @tag_email_on_failure "email_on_failure"

  @doc """
  If you add this tag to an `Oban.Job`, if this job fails an email will be sent
  to the tech team alias to warn about this failure.

  ⚠️ Do not use this on a lot of jobs or jobs that are executed often, this is not a Sentry replacement! ⚠️
  This should soon be replaced by a Sentry integration.
  """
  def email_on_failure_tag, do: @tag_email_on_failure

  def handle_event(
        [:oban, :job, :exception],
        %{duration: duration},
        %{
          args: args,
          error: error,
          id: id,
          worker: worker,
          job: %Oban.Job{tags: tags, attempt: attempt, max_attempts: max_attempts}
        },
        nil
      ) do
    if email_on_failure_tag() in tags and attempt == max_attempts do
      worker |> Transport.AdminNotifier.oban_failure() |> Transport.Mailer.deliver()
    end

    Logger.warning(
      "Job #{id} handled by #{worker} called with args #{inspect(args)} failed in #{duration}. Error: #{inspect(error)}"
    )
  end

  def setup, do: :telemetry.attach("oban-logger", [:oban, :job, :exception], &handle_event/4, nil)
end
