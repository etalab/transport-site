defmodule Transport.Jobs.Workflow do
  @moduledoc """
   Handle a simple workflow of jobs.
  """
  use Oban.Worker, tags: ["workflow"], max_attempts: 3

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"jobs" => jobs, "args" => args}}) do
    :ok = Oban.Notifier.listen([:gossip])
    execute_jobs(jobs, args)
    :ok
  end

  defp execute_jobs([job], args), do: insert_job(job, args)

  defp execute_jobs([job | tail], args) do
    %{id: job_id} = insert_job(job, args)

    receive do
      # each job produces an output than can be used by the next job in the workflow
      {:notification, :gossip, %{"complete" => ^job_id, "output" => job_output}} ->
        execute_jobs(tail, job_output)
    end
  end

  def insert_job({job_name, custom_args, options}, args) do
    # if custom args are given they are merged with the job arguments
    # options are job options (unique, ...)
    args = Map.merge(args, custom_args)
    String.to_existing_atom(job_name).new(args, options) |> Oban.insert!()
  end

  def insert_job(job_name, args) do
    String.to_existing_atom(job_name).new(args) |> Oban.insert!()
  end

  def notify_workflow(args) do
    Oban.Notifier.notify(Oban, :gossip, args)
  end
end
