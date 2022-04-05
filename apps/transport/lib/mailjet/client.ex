defmodule Mailjet.Client do
  @moduledoc """
    Helper to send mail via mailjet
  """
  require Logger
  @behaviour Transport.EmailSender

  def get_config!(key) do
    config = Application.fetch_env!(:transport, __MODULE__)
    Keyword.fetch!(config, key)
  end

  def mailjet_user, do: get_config!(:mailjet_user)
  def mailjet_key, do: get_config!(:mailjet_key)
  def mailjet_url, do: get_config!(:mailjet_url)
  def httpoison_impl, do: Application.fetch_env!(:transport, :httpoison_impl)

  @spec payload!(binary(), binary(), binary(), binary(), binary(), binary()) :: any()
  def payload!(from_name, from_email, to_email, reply_to, topic, text_body, html_body \\ nil) do
    Jason.encode!(%{
      Messages: [
        %{
          From: %{Name: from_name, Email: from_email},
          To: [%{Email: to_email}],
          Subject: topic,
          TextPart: text_body,
          HtmlPart: html_body,
          ReplyTo: %{Email: reply_to}
        }
      ]
    })
  end

  @impl Transport.EmailSender
  def send_mail(from_name, from_email, to_email, reply_to, topic, text_body, html_body) do
    mailjet_url()
    |> httpoison_impl().post(payload!(from_name, from_email, to_email, reply_to, topic, text_body, html_body), nil,
      hackney: [basic_auth: {mailjet_user(), mailjet_key()}]
    )
    |> case do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: _, body: body}} -> {:error, body}
      {:error, error} -> {:error, error}
    end
  end
end
