defmodule Transport.Repo do
  use Ecto.Repo,
    otp_app: :transport,
    adapter: Ecto.Adapters.Postgres
end
