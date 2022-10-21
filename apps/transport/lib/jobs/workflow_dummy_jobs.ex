defmodule Transport.Jobs.Dummy do
  @moduledoc """
  dummy jobs used to test job workflows
  """
  defmodule JobA do
    @moduledoc """
    a dummy job A
    """
    use Oban.Worker

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
      # this job increments an id
      some_id = some_id + 1

      # A real worker would use Transport.Jobs.Workflow.notify_workflow,
      # but for testing, we just send a similar message to the parent
      send(
        :workflow_process,
        {:notification, :gossip, %{"success" => true, "job_id" => job.id, "output" => %{"some_id" => some_id}}}
      )

      :ok
    end
  end

  defmodule JobB do
    @moduledoc """
    a dummy job B
    """
    use Oban.Worker

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
      some_id = some_id + 1

      send(
        :workflow_process,
        {:notification, :gossip, %{"success" => true, "job_id" => job.id, "output" => %{"some_id" => some_id}}}
      )

      :ok
    end
  end

      :ok
    end
  end
end
