use Mix.Config

alias Transport.Mailgun.Client

config :transport, Client,
  mailgun_domain: System.get_env("MAILGUN_DOMAIN"),
  apikey: System.get_env("MAILGUN_API_KEY"),
  mailgun_url: "https://api.mailgun.net/v3/"
