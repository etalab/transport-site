import Config

config :transport, Mailjet.Client,
  mailjet_user: System.get_env("MJ_APIKEY_PUBLIC"),
  mailjet_key: System.get_env("MJ_APIKEY_PRIVATE"),
  mailjet_url: "https://api.mailjet.com/v3.1/send"

config :transport, :email_sender_impl, Mailjet.Client
