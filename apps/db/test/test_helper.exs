ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
Mox.defmock(Transport.HTTPoison.Mock, for: HTTPoison.Base)
