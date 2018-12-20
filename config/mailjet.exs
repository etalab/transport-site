use Mix.Config

alias Mailjet.Client

config :mailjet, Client,
  user: System.get_env("MJ_APIKEY_PUBLIC"),
  key: System.get_env("MJ_APIKEY_PRIVATE"),
  url: "https://api.mailjet.com/v3.1/send"
