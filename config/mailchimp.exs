import Config

# Configure mailchimp
config :transport, mailchimp_newsletter_url: System.get_env("MAILCHIMP_NEWSLETTER_URL")
