defmodule Transport.Application do
  @moduledoc """
  See https://hexdocs.pm/elixir/Application.html
  for more information on OTP Applications
  """

  use Application
  use Task
  alias Transport.{CSVDocuments, ImportDataWorker, SearchCommunes}
  alias TransportWeb.Endpoint
  import Supervisor.Spec, only: [supervisor: 2]

  def start(_type, _args) do
    children =
      [
        supervisor(TransportWeb.Endpoint, []),
        supervisor(ImportDataWorker, []),
        CSVDocuments,
        SearchCommunes,
        {Phoenix.PubSub, [name: TransportWeb.PubSub, adapter: Phoenix.PubSub.PG2]}
      ]
      |> add_scheduler()
      ## manually add a children supervisor that is not scheduled
      |> Kernel.++([{Task.Supervisor, name: ImportTaskSupervisor}])

    opts = [strategy: :one_for_one, name: Transport.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp add_scheduler(children) do
    if Mix.env() != :test do
      import Supervisor.Spec, only: [worker: 2]
      [worker(Transport.Scheduler, []) | children]
    else
      children
    end
  end

  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
