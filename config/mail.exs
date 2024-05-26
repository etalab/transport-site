import Config

# Swoosh config. Do not send emails (in staging…), but instead log something.
# Prod is configured in runtime.exs, and dev preview mailbox in dev.exs
config :transport, Transport.Mailer,
  adapter: Swoosh.Adapters.Logger,
  level: :debug
