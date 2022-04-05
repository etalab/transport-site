defmodule Transport.EmailSender do
  # NOTE: it would be better to refactor this into the use of a map,
  # but at time of writing I'm minimizing the size of the refactoring.
  @callback send_mail(
              from_name :: binary(),
              from_email :: binary(),
              to_email :: binary(),
              reply_to :: binary(),
              topic :: binary(),
              text_body :: binary(),
              html_body :: binary()
            ) :: {:ok, any()} | {:error, any()}
  def impl, do: Application.fetch_env!(:transport, :email_sender_impl)
end
