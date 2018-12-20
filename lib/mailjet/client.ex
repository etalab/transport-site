defmodule Mailjet.Client do
  @moduledoc """
    Helper to send mail via mailjet
  """
  use HTTPoison.Base

  @user Application.get_env(:transport, __MODULE__)[:mailjet_user]
  @key Application.get_env(:transport, __MODULE__)[:mailjet_key]
  @url Application.get_env(:transport, __MODULE__)[:mailjet_url]

  def payload!(sender, topic, body) do
    Poison.encode!(%{"Messages": [%{
        "From": %{"Name": "PAN, Formulaire Contact", "Email": "contact@transport.beta.gouv.fr"},
        "To": [%{"Email": "contact@transport.beta.gouv.fr"}],
        "Subject": topic,
        "TextPart": body,
        "ReplyTo": %{"Email": sender}
      }]
    })
  end

  def send_mail(sender, topic, body) do
    @url
    |> post(payload!(sender, topic, body))
    |> case do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: _, body: body}}   -> {:error, body}
      {:error, error}                        -> {:error, error}
    end
  end

  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    options = options ++ [hackney: [basic_auth: {@user, @key}]]
    super(method, url, body, headers, options)
  end

end
