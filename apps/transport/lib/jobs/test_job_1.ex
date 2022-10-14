defmodule Transport.Jobs.TestJobA do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    IO.inspect("A #{some_id}")
    Oban.Notifier.notify(Oban, :gossip, %{complete: job.id, infos: %{"some_id" => some_id}})
    :ok
  end
end

defmodule Transport.Jobs.TestJobB do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    IO.inspect("B #{some_id}")
    Oban.Notifier.notify(Oban, :gossip, %{complete: job.id, infos: %{"some_id" => some_id + 1}})
    :ok
  end
end

defmodule Transport.Jobs.TestJobC do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id}} = job) do
    IO.inspect("C #{some_id}")
    Oban.Notifier.notify(Oban, :gossip, %{complete: job.id, infos: %{"some_id" => some_id + 1}})
    :ok
  end
end

defmodule Transport.Jobs.Call do
  def go do
    jobs = [
      Transport.Jobs.TestJobA,
      Transport.Jobs.TestJobB,
      Transport.Jobs.TestJobC
    ]

    # jobs = [{Transport.Jobs.TestJobA, %{some_id: 1}}]

    :ok = Oban.Notifier.listen([:gossip])
    execute_jobs(jobs, %{some_id: 1})
  end

  def execute_jobs([job], args), do: job.new(args) |> Oban.insert!()

  def execute_jobs([job | tail], args) do
    %{id: job_id} = job.new(args) |> Oban.insert!()

    receive do
      {:notification, :gossip, %{"complete" => ^job_id, "infos" => infos}} ->
        IO.puts("Other job complete!")
        execute_jobs(tail, infos)
    after
      30_000 ->
        IO.puts("Other job didn't finish in 30 seconds!")
    end
  end
end
