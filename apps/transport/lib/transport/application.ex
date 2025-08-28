defmodule Transport.Application do
  require Logger

  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application
  use Task
  import Cachex.Spec
  alias Transport.{CachedFiles, ImportDataWorker, SearchCommunes}
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
        DB.Repo,
        {Cachex, name: @cache_name},
        TransportWeb.Endpoint,
        ImportDataWorker,
        CachedFiles,
        SearchCommunes,
        {Phoenix.PubSub, [name: TransportWeb.PubSub, adapter: Phoenix.PubSub.PG2]},
        TransportWeb.Presence,
        # Oban is "always started", but muted via `config/runtime.exs` for cases like
        # tests, IEx usage, front-end only mode etc.
        {Oban, Application.fetch_env!(:transport, Oban)},
        Transport.PhoenixDashboardTelemetry,
        Transport.Vault,
        Unlock.Endpoint,
        {Finch, name: Unlock.Finch},
        Supervisor.child_spec(
          {Cachex,
           name: Unlock.Cachex,
           expiration: expiration(default: :timer.seconds(Unlock.Shared.default_cache_expiration_seconds()))},
          id: :unlock_cachex
        )
      ]
      |> add_scheduler()
      |> add_if(fn -> run_realtime_poller?() end, Transport.RealtimePoller)
      |> add_if(fn -> preemptive_caching?() end, Transport.PreemptiveHomeStatsCache)
      |> add_if(fn -> preemptive_caching?() end, Transport.PreemptiveAPICache)
      |> add_if(fn -> preemptive_caching?() end, Transport.PreemptiveStatsCache)
      |> add_if(fn -> enforce_ttl?() end, Unlock.EnforceTTL)
      ## manually add a children supervisor that is not scheduled
      |> Kernel.++([{Task.Supervisor, name: ImportTaskSupervisor}])

    :ok = Transport.Jobs.ObanLogger.setup()

    :ok = Transport.Telemetry.setup()
    :ok = Transport.AppSignal.EctoTelemetry.setup()

    opts = [strategy: :one_for_one, name: Transport.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def webserver_enabled?, do: Application.fetch_env!(:transport, :webserver)
  def worker_enabled?, do: Application.fetch_env!(:transport, :worker)
  def worker_only?, do: worker_enabled?() && !webserver_enabled?()
  def webserver_only?, do: webserver_enabled?() && !worker_enabled?()
  def dual_mode?, do: worker_enabled?() && webserver_enabled?()

  def run_realtime_poller?, do: webserver_enabled?() && Mix.env() != :test

  def preemptive_caching?,
    do: webserver_enabled?() && Application.fetch_env!(:transport, :app_env) in [:production, :staging]

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

  defp enforce_ttl?, do: Application.fetch_env!(:transport, :unlock_enforce_ttl)

  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
