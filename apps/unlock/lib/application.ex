defmodule Unlock.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Unlock.Endpoint,
      {Finch, name: Unlock.Finch},
      {Cachex, name: Unlock.Cachex}
    ]

    opts = [strategy: :one_for_one, name: Unlock.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # NOTE: not implementing `config_change` at this point, but in case
  # you can read about it here:
  # https://github.com/phoenixframework/phoenix/issues/3025
end
