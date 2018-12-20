use Mix.Config

alias Mailjet.Client

config :transport, Client,
  mailjet_user: System.get_env("MJ_APIKEY_PUBLIC"),
  mailjet_key: System.get_env("MJ_APIKEY_PRIVATE"),
  mailjet_url: "https://api.mailjet.com/v3.1/send"
