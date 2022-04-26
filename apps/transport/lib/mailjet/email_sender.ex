defmodule Transport.EmailSender do
  @moduledoc """
  A wrapper for email sending, that we can use to mock out email sending operations during tests.
  """

  # NOTE: it would be better to refactor this into the use of a map,
  # but at time of writing I'm minimizing the size of the refactoring.
  @callback send_mail(
              from_name :: binary(),
              from_email :: binary(),
              to_email :: binary(),
              reply_to :: binary(),
              subject :: binary(),
              text_body :: binary(),
              html_body :: binary()
            ) :: {:ok, any()} | {:error, any()}
  def impl, do: Application.fetch_env!(:transport, :email_sender_impl)
end

defmodule Transport.EmailSender.Dummy do
  require Logger

  @moduledoc """
  A development-time implementation which just happens to log to console
  """

  def send_mail(_from_name, from_email, to_email, _reply_to, topic, _text_body, _html_body) do
    Logger.info("Would send email: from #{from_email} to #{to_email}, topic '#{topic}'")
  end
end
