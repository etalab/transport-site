defmodule Db.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      DB.Repo
    ]

    opts = [strategy: :one_for_one, name: Db.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
