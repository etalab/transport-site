defmodule Transport.Application do
  require Logger

  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application
  use Task
  alias Transport.{CSVDocuments, ImportDataWorker, SearchCommunes}
  alias TransportWeb.Endpoint

  @cache_name :transport
  # for DRY external reference
  def cache_name, do: @cache_name

  def start(_type, _args) do
    unless Mix.env() == :test do
      cond do
        worker_only?() -> Logger.info("Booting in worker-only mode...")
        webserver_only?() -> Logger.info("Booting in webserver-only mode...")
        dual_mode?() -> Logger.info("Booting in worker+webserver mode...")
      end
    end

    children =
      [
        {Cachex, name: @cache_name},
        TransportWeb.Endpoint,
        ImportDataWorker,
        CSVDocuments,
        SearchCommunes,
        {Phoenix.PubSub, [name: TransportWeb.PubSub, adapter: Phoenix.PubSub.PG2]},
        # Oban is "always started", but muted via `config/runtime.exs` for cases like
        # tests, IEx usage, front-end only mode etc.
        {Oban, Application.fetch_env!(:transport, Oban)}
      ]
      |> add_scheduler()
      |> add_if(fn() -> Mix.env() != :test && webserver_enabled?() end, Transport.RealtimePoller)
      ## manually add a children supervisor that is not scheduled
      |> Kernel.++([{Task.Supervisor, name: ImportTaskSupervisor}])

    :ok = Transport.ObanLogger.setup()

    :ok = Transport.Telemetry.setup()

    opts = [strategy: :one_for_one, name: Transport.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def webserver_enabled?, do: Application.fetch_env!(:transport, :webserver)
  def worker_enabled?, do: Application.fetch_env!(:transport, :worker)
  def worker_only?, do: worker_enabled?() && !webserver_enabled?()
  def webserver_only?, do: webserver_enabled?() && !worker_enabled?()
  def dual_mode?, do: worker_enabled?() && webserver_enabled?()


  defp add_if(children, condition, child) do
    if condition.() do
      children ++ [child]
    else
      children
    end
  end

  defp add_scheduler(children) do
    if Mix.env() != :test do
      [Transport.Scheduler | children]
    else
      children
    end
  end

  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
