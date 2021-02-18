defmodule Mailjet.Client do
  @moduledoc """
    Helper to send mail via mailjet
  """
  use HTTPoison.Base
  require Logger

  def mailjet_user, do: Application.get_env(:transport, __MODULE__)[:mailjet_user]
  def mailjet_key, do: Application.get_env(:transport, __MODULE__)[:mailjet_key]
  def mailjet_url, do: Application.get_env(:transport, __MODULE__)[:mailjet_url]

  @spec payload!(binary(), binary(), binary(), binary(), binary()) :: any()
  def payload!(from_name, from_email, reply_to, topic, body) do
    Jason.encode!(%{
      Messages: [
        %{
          From: %{Name: from_name, Email: from_email},
          To: [%{Email: "contact@transport.beta.gouv.fr"}],
          Subject: topic,
          TextPart: body,
          ReplyTo: %{Email: reply_to}
        }
      ]
    })
  end

  @spec send_mail(binary, binary, binary, binary, binary, boolean) :: {:error, any} | {:ok, any}
  def send_mail(from_name, from_email, reply_to, topic, body, true) do
    Logger.debug(fn -> "payload: #{payload!(from_name, from_email, reply_to, topic, body)}" end)
    {:ok, body}
  end

  def send_mail(from_name, from_email, reply_to, topic, body, false) do
    mailjet_url()
    |> post(payload!(from_name, from_email, reply_to, topic, body))
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
