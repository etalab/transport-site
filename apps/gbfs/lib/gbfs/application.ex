defmodule GBFS.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  alias GBFS.Endpoint

  @cache_name :gbfs
  # for external reference
  def cache_name, do: @cache_name

  def start(_type, _args) do
    children = [
      {Cachex, name: @cache_name},
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
