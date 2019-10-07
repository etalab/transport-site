defmodule DB.Repo do
  use Ecto.Repo,
    otp_app: :db,
    adapter: Ecto.Adapters.Postgres
  use Scrivener, page_size: 10
end
