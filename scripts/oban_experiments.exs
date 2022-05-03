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

  def main do
    children = [
      Repo,
      {Oban, repo: Repo, plugins: [Oban.Plugins.Pruner], queues: [default: 10]}
    ]

    Logger.info "Erasing database..."
    Repo.__adapter__().storage_down(Repo.config())

    Logger.info "Creating database..."
    Repo.__adapter__().storage_up(Repo.config())

    {:ok, _} = Supervisor.start_link(children, strategy: :one_for_one)

    Logger.info "Running migrations..."
    Ecto.Migrator.run(Repo, [{0, Migration0}], :up, all: true)

    Logger.info "Inserting long running job..."
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
      Logger.info "Working (step #{i} of #{max})..."
      Process.sleep(1_000)
    end
    :ok
  end
end

Main.main()

Process.sleep(5_000)

Process.sleep(100_000)
