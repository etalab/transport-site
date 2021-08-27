ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
Mox.defmock(Transport.HTTPoison.Mock, for: HTTPoison.Base)
Mox.defmock(DB.Resource.GtfsTransportValidator.Mock, for: DB.Resource.Validator)
