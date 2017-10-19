use Mix.Config

# Configure amqp
config :amqp, rabbitmq_url: System.get_env("RABBITMQ_URL")
