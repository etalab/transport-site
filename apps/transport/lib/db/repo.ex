defmodule DB.Repo do
  use Ecto.Repo,
    otp_app: :transport,
    adapter: Ecto.Adapters.Postgres

  use Scrivener, page_size: 20
end
