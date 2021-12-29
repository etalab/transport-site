defmodule Unlock.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application
  import Cachex.Spec

  def start(_type, _args) do
    children =
      [
        Unlock.Endpoint,
        {Finch, name: Unlock.Finch},
        {Cachex,
         name: Unlock.Cachex,
         expiration: expiration(default: :timer.seconds(Unlock.Shared.default_cache_expiration_seconds()))}
      ]
      |> prepend_if(webserver?(), Unlock.EnforceTTL)

    opts = [strategy: :one_for_one, name: Unlock.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp prepend_if(list, condition, item) do
    if condition, do: [item | list], else: list
  end

  defp webserver?, do: Application.fetch_env!(:transport, :webserver)

  # NOTE: not implementing `config_change` at this point, but in case
  # you can read about it here:
  # https://github.com/phoenixframework/phoenix/issues/3025
end
