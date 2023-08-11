defmodule Transport.Jobs.ObanLogger do
  @moduledoc """
  Logs the Oban job exceptions as warnings
  """
  require Logger
  @tag_email_on_failure "email_on_failure"

  def email_on_failure_tag, do: @tag_email_on_failure

  def handle_event(
        [:oban, :job, :exception],
        %{duration: duration},
        %{args: args, error: error, id: id, worker: worker, job: %Oban.Job{tags: tags}} = meta,
        nil
      ) do
    if email_on_failure_tag() in tags do
      send_email_to_tech(meta)
    end

    Logger.warning(
      "Job #{id} handled by #{worker} called with args #{inspect(args)} failed in #{duration}. Error: #{inspect(error)}"
    )
  end

  def setup, do: :telemetry.attach("oban-logger", [:oban, :job, :exception], &handle_event/4, nil)

  defp send_email_to_tech(%{worker: worker}) do
    Transport.EmailSender.impl().send_mail(
      "transport.data.gouv.fr",
      Application.get_env(:transport, :contact_email),
      Application.get_env(:transport, :tech_email),
      Application.get_env(:transport, :contact_email),
      "Échec de job Oban : #{worker}",
      "Un job Oban #{worker} vient d'échouer, il serait bien d'investiguer.",
      ""
    )
  end
end
