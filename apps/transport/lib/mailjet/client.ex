defmodule Mailjet.Client do
  @moduledoc """
    Helper to send mail via mailjet
  """
  use HTTPoison.Base
  require Logger

  @user Application.get_env(:transport, __MODULE__)[:mailjet_user]
  @key Application.get_env(:transport, __MODULE__)[:mailjet_key]
  @url Application.get_env(:transport, __MODULE__)[:mailjet_url]

  @spec payload!(binary(), binary(), binary(), binary(), binary()) :: any()
  def payload!(from_name, from_email, reply_to, topic, text_body, html_body \\ nil) do
    Jason.encode!(%{
      Messages: [
        %{
          From: %{Name: from_name, Email: from_email},
          To: [%{Email: "contact@transport.beta.gouv.fr"}],
          Subject: topic,
          TextPart: text_body,
          HtmlPart: html_body,
          ReplyTo: %{Email: reply_to}
        }
      ]
    })
  end

  @spec send_mail(binary, binary, binary, binary, binary, binary, boolean) :: {:error, any} | {:ok, any}
  def send_mail(from_name, from_email, reply_to, topic, text_body, html_body, true) do
    Logger.debug(fn -> "payload: #{payload!(from_name, from_email, reply_to, topic, text_body, html_body)}" end)
    {:ok, text_body || html_body}
  end

  def send_mail(from_name, from_email, reply_to, topic, text_body, html_body, false) do
    @url
    |> post(payload!(from_name, from_email, reply_to, topic, text_body, html_body))
    |> case do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: _, body: body}} -> {:error, body}
      {:error, error} -> {:error, error}
    end
  end

  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    options = options ++ [hackney: [basic_auth: {@user, @key}]]
    super(method, url, body, headers, options)
  end
end
