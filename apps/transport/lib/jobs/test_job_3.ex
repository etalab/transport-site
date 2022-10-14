defmodule Transport.Jobs.TestJobA3 do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    IO.inspect("A #{some_id}")
    :timer.sleep(5000)
    Oban.Notifier.notify(Oban, :gossip, %{complete: job.id, infos: %{"some_id" => some_id}})
    :ok
  end
end

defmodule Transport.Jobs.TestJobB3 do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    IO.inspect("B #{some_id}")
    :timer.sleep(5000)
    Oban.Notifier.notify(Oban, :gossip, %{complete: job.id, infos: %{"some_id" => some_id + 1}})
    :ok
  end
end

defmodule Transport.Jobs.TestJobC3 do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    IO.inspect("C #{some_id}")
    :timer.sleep(5000)
    Oban.Notifier.notify(Oban, :gossip, %{complete: job.id, infos: %{"some_id" => some_id + 1}})
    :ok
  end
end

defmodule Transport.Jobs.Call3 do
  def go do
    jobs = [
      Transport.Jobs.TestJobA3,
      Transport.Jobs.TestJobB3,
      Transport.Jobs.TestJobC3
    ]

    Transport.Jobs.Workflow.new(%{jobs: jobs, args: %{some_id: 1}}) |> Oban.insert!()
    :ok
  end
end

defmodule Transport.Jobs.Workflow do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"jobs" => jobs, "args" => args}}) do
    :ok = Oban.Notifier.listen([:gossip])
    execute_jobs(jobs, args)
    :ok
  end

  def execute_jobs([job], args), do: String.to_existing_atom(job).new(args) |> Oban.insert!()

  def execute_jobs([job | tail], args) do
    %{id: job_id} = String.to_existing_atom(job).new(args) |> Oban.insert!()

    receive do
      {:notification, :gossip, %{"complete" => ^job_id, "infos" => infos}} ->
        IO.puts("Other job complete!")
        execute_jobs(tail, infos)
    end
  end
end
