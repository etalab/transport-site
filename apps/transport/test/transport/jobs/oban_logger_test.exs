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
  import Swoosh.TestAssertions

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

    assert_no_email_sent()

    # Should be sent when failing at the last attempt
    assert {:error, "failed"} ==
             perform_job(Transport.Test.Transport.Jobs.ObanLoggerJobTag, %{},
               tags: [Transport.Jobs.ObanLogger.email_on_failure_tag()],
               attempt: 2,
               max_attempts: 2
             )

    assert_email_sent(
      from: {"transport.data.gouv.fr", "contact@transport.data.gouv.fr"},
      to: "tech@transport.data.gouv.fr",
      subject: "Échec de job Oban : Transport.Test.Transport.Jobs.ObanLoggerJobTag",
      text_body:
        "Un job Oban Transport.Test.Transport.Jobs.ObanLoggerJobTag vient d'échouer, il serait bien d'investiguer."
    )
  end

  test "oban default logger is set up for important components" do
    registered_handlers = Enum.filter(:telemetry.list_handlers([]), &(&1.id == "oban-default-logger"))

    assert Enum.count(registered_handlers) > 0

    components =
      registered_handlers
      |> Enum.map(fn %{event_name: [:oban, component, _]} -> component end)
      |> MapSet.new()

    assert MapSet.new([:notifier, :queue, :stager]) == MapSet.new(components)
  end
end
