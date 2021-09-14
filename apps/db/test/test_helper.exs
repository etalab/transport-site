ExUnit.start()

Ecto.Adapters.SQL.Sandbox.mode(DB.Repo, :manual)
Mox.defmock(Transport.HTTPoison.Mock, for: HTTPoison.Base)
Mox.defmock(Validation.Validator.Mock, for: Shared.Validation.Validator)
