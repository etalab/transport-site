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

      Transport.Jobs.Workflow.Notifier.notify_workflow(job, %{
        "success" => true,
        "job_id" => job.id,
        "output" => %{"some_id" => some_id}
      })

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

      Transport.Jobs.Workflow.Notifier.notify_workflow(job, %{
        "success" => true,
        "job_id" => job.id,
        "output" => %{"some_id" => some_id}
      })

      :ok
    end
  end

  defmodule FailingJob do
    @moduledoc """
    a dummy job that fails if the input is not 0
    """
    use Oban.Worker, max_attempts: 1

    @impl Oban.Worker
    def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
      if some_id != 0 do
        {:error, "job fails"}
      else
        Transport.Jobs.Workflow.Notifier.notify_workflow(job, %{
          "success" => true,
          "job_id" => job.id,
          "output" => %{"some_id" => some_id}
        })

        :ok
      end
    end
  end
end
