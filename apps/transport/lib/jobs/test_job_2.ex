defmodule Transport.Jobs.Call2 do
  def go do
    jobs = [
      Transport.Jobs.TestJobA2,
      Transport.Jobs.TestJobB2,
      Transport.Jobs.TestJobC2
    ]

    execute_jobs(jobs, %{some_id: 1})
  end

  def execute_jobs([job], args), do: job.new(args) |> Oban.insert!()

  def execute_jobs([job | tail], args) do
    oban_args = Map.merge(%{next_jobs: tail}, args)
    job.new(oban_args) |> Oban.insert!()
  end

  def execute_next_jobs(_args, []), do: :ok

  def execute_next_jobs(args, [next_job | tail]) do
    oban_args = Map.merge(args, %{next_jobs: tail})
    next_job = String.to_existing_atom(next_job)
    next_job.new(oban_args) |> Oban.insert!()
  end
end

defmodule Transport.Jobs.TestJobA2 do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id} = args}) do
    IO.inspect("A #{some_id}")

    Transport.Jobs.Call2.execute_next_jobs(%{"some_id" => some_id + 1}, Map.get(args, "next_jobs", []))
    :ok
  end
end

defmodule Transport.Jobs.TestJobB2 do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id} = args}) do
    IO.inspect("B #{some_id}")

    Transport.Jobs.Call2.execute_next_jobs(%{"some_id" => some_id + 1}, Map.get(args, "next_jobs", []))
    :ok
  end
end

defmodule Transport.Jobs.TestJobC2 do
  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"some_id" => some_id} = args}) do
    IO.inspect("C #{some_id}")

    Transport.Jobs.Call2.execute_next_jobs(%{"some_id" => some_id + 1}, Map.get(args, "next_jobs", []))
    :ok
  end
end
