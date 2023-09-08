defmodule Transport.Mailer do
  use Swoosh.Mailer, otp_app: :transport

  @moduledoc """
  A mailer built on top of Swoosh, see documentation here https://hexdocs.pm/swoosh/Swoosh.html
  The main Swoosh package provides most functionality (including dev preview and test functionality).
  Phoenix.Swoosh just adds the ability to render views and templates https://hexdocs.pm/phoenix_swoosh/readme.html
  You need to have a module that actually generates mails, either just importing Swoosh.Email if you don’t need templates, either using Phoenix.Swoosh if you do, and then the emails are passed to this module to be actually sent.
  For now it uses Mailjet as a provider (see config/config.exs), but it could be changed to another provider if needed.
  """
end
