use ExGuard.Config

guard("gettext extract merge", run_on_start: true)
|> command("mix gettext.extract --merge")
|> watch(~r{\.(eex)\z}i)
