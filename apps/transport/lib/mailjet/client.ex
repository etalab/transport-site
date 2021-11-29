defmodule Mailjet.Client do
  @moduledoc """
    Helper to send mail via mailjet
  """
  use HTTPoison.Base
  require Logger

  def get_config!(key) do
    config = Application.fetch_env!(:transport, __MODULE__)
    Keyword.fetch!(config, key)
  end

  def mailjet_user, do: get_config!(:mailjet_user)
  def mailjet_key, do: get_config!(:mailjet_key)
  def mailjet_url, do: get_config!(:mailjet_url)

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

  @spec send_mail(binary, binary, binary, binary, binary, binary, binary, boolean) :: {:error, any} | {:ok, any}
  def send_mail(from_name, from_email, to_email, reply_to, topic, text_body, html_body, true) do
    Logger.debug(fn ->
      "payload: #{payload!(from_name, from_email, to_email, reply_to, topic, text_body, html_body)}"
    end)

    {:ok, text_body || html_body}
  end

  def send_mail(from_name, from_email, to_email, reply_to, topic, text_body, html_body, false) do
    mailjet_url()
    |> post(payload!(from_name, from_email, to_email, reply_to, topic, text_body, html_body))
    |> case do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: _, body: body}} -> {:error, body}
      {:error, error} -> {:error, error}
    end
  end

  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    options = options ++ [hackney: [basic_auth: {mailjet_user(), mailjet_key()}]]
    super(method, url, body, headers, options)
  end
end
