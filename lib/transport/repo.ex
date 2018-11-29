defmodule Transport.Repo do
  use Ecto.Repo,
    otp_app: :transport,
    adapter: Ecto.Adapters.Postgres
  use Scrivener, page_size: 10
end
