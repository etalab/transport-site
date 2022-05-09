require Logger

Mix.install([
  {:ecto_sql, "~> 3.8.1"},
  {:postgrex, "~> 0.16.3"},
  {:oban, "~> 2.12"}
])

Application.put_env(:myapp, Repo, database: "test_oban")

defmodule Repo do
  use Ecto.Repo,
    adapter: Ecto.Adapters.Postgres,
    otp_app: :myapp
end

defmodule Migration0 do
  use Ecto.Migration

  def change do
    Oban.Migrations.up()
  end
end

defmodule Main do
  require Logger

  def start_ecto do
    children = [
      Repo,
      {Oban, repo: Repo, plugins: [Oban.Plugins.Pruner], queues: [default: 10]}
    ]

    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)
  end

  def create_db do
    Logger.info("Erasing database...")
    Repo.__adapter__().storage_down(Repo.config())

    Logger.info("Creating database...")
    Repo.__adapter__().storage_up(Repo.config())
  end

  def main do
    start_ecto()

    Logger.info("Running migrations...")
    Ecto.Migrator.run(Repo, [{0, Migration0}], :up, all: true)

    Logger.info("Inserting long running job...")
    Oban.insert!(LongRunningJob.new(%{}))

    # Oban.Job
    # |> Repo.all()
    # |> IO.inspect(IEx.inspect_opts)
  end
end

defmodule LongRunningJob do
  use Oban.Worker
  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    max = 10_000

    for i <- 1..max do
      Logger.info("Working (step #{i} of #{max})...")
      Process.sleep(1_000)
    end

    :ok
  end
end

case System.argv() do
  ["create_db"] ->
    Main.create_db()

  ["check"] ->
    Main.start_ecto()

    [job] =
      Oban.Job
      |> Repo.all(log: false)
      |> Enum.map(fn x -> Map.take(x, [:attempt, :state]) end)
      |> IO.inspect(IEx.inspect_opts())

  ["run"] ->
    Logger.info("Starting individual process running a very long time")
    Main.main()
    Process.sleep(10_000_000)
end
