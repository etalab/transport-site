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
      # TODO: evaluate if we really need this - I believe we don't
      {Phoenix.PubSub, [name: GBFS.PubSub, adapter: Phoenix.PubSub.PG2]},
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
