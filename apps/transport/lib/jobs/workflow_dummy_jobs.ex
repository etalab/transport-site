defmodule Transport.Jobs.JobATest do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    # this job increments an id
    some_id = some_id + 1

    # A real worker would use Transport.Jobs.Workflow.notify_workflow,
    # but for testing, we just send a similar message to the parent
    send(:workflow_process, {:notification, :gossip, %{"complete" => job.id, "output" => %{"some_id" => some_id}}})
    :ok
  end
end

defmodule Transport.Jobs.JobBTest do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    some_id = some_id + 1
    send(:workflow_process, {:notification, :gossip, %{"complete" => job.id, "output" => %{"some_id" => some_id}}})
    :ok
  end
end
