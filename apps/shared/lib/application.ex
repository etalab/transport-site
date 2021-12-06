defmodule Shared.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Used for streaming component, see possible config at:
      # https://github.com/keathley/finch#usage
      {Finch,
       name: Transport.Finch,
       pools: %{
         # slightly larger than default
         :default => [size: 25]
       }}
    ]

    opts = [strategy: :one_for_one, name: Shared.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
