defmodule Transport.Application do
  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application
  alias Transport.Repo
  alias TransportWeb.Endpoint

  def start(_type, _args) do
    import Supervisor.Spec, only: [supervisor: 2]

    # Define workers and child supervisors to be supervised
    children = [
      # Start the endpoint when the application starts
      supervisor(Registry, [:unique, :dataset_registry]),
      supervisor(TransportWeb.Endpoint, []),
      Repo
      # Start worker by calling: Transport.Worker.start_link(arg1, arg2, arg3)
      # worker(Transport.Worker, [arg1, arg2, arg3]),
    ]
    |> add_scheduler()

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Transport.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp add_scheduler(children) do
    if Mix.env != :test do
      import Supervisor.Spec, only: [worker: 2]
      [worker(Transport.Scheduler, []) | children]
    else
      children
    end
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
