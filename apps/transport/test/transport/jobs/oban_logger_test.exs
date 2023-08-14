defmodule Transport.Test.Transport.Jobs.ObanLoggerJobTag do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {:error, "failed"}
  end
end

defmodule Transport.Test.Transport.Jobs.ObanLoggerTest do
  use ExUnit.Case, async: true
  @moduletag :capture_log
  use Oban.Testing, repo: DB.Repo
  import Mox

  setup :verify_on_exit!

  test "sends an email on failure if the appropriate tag is set" do
    assert {:error, "failed"} == perform_job(Transport.Test.Transport.Jobs.ObanLoggerJobTag, %{}, tags: [])

    # When the specific tag is set, an email should be sent

    # Should not be sent when not trying for the last time
    assert {:error, "failed"} ==
             perform_job(Transport.Test.Transport.Jobs.ObanLoggerJobTag, %{},
               tags: [Transport.Jobs.ObanLogger.email_on_failure_tag()],
               attempt: 1,
               max_attempts: 2
             )

    # Should be sent when failing at the last attempt
    Transport.EmailSender.Mock
    |> expect(:send_mail, fn "transport.data.gouv.fr",
                             "contact@transport.beta.gouv.fr",
                             "tech@transport.data.gouv.fr" = _to,
                             "contact@transport.beta.gouv.fr",
                             "Échec de job Oban : Transport.Test.Transport.Jobs.ObanLoggerJobTag" = _subject,
                             plain_text_body,
                             "" = _html_part ->
      assert plain_text_body ==
               "Un job Oban Transport.Test.Transport.Jobs.ObanLoggerJobTag vient d'échouer, il serait bien d'investiguer."

      :ok
    end)

    assert {:error, "failed"} ==
             perform_job(Transport.Test.Transport.Jobs.ObanLoggerJobTag, %{},
               tags: [Transport.Jobs.ObanLogger.email_on_failure_tag()],
               attempt: 2,
               max_attempts: 2
             )
  end
end
