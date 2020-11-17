defmodule GBFS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias GBFS.Endpoint

  def start(_type, _args) do
    children = [
      {Cachex, name: :gbfs},
      Endpoint
    ]

    opts = [strategy: :one_for_one, name: GBFS.Supervisor]
    Supervisor.start_link(children, opts)
  end

  def config_change(changed, _new, removed) do
    Endpoint.config_change(changed, removed)
    :ok
  end
end
