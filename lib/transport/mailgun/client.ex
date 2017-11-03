defmodule Transport.Mailgun.Client do
  @moduledoc """
    Helper to send mail via mailgun
  """
  use HTTPoison.Base

  @domain  Application.get_env(:transport, __MODULE__)[:mailgun_domain]
  @url Application.get_env(:transport, __MODULE__)[:mailgun_url]
  @apikey Application.get_env(:transport, __MODULE__)[:apikey]

  def send_mail(sender, body) do
    [@url, @domain, "messages"]
    |> Path.join()
    |> post({:form, [{"from",  "anonymous <" <> sender <> ">"},
                     {"to", "contact@transport.beta.gouv.fr"},
                     {"subject", "Question sur transport.data.gouv.fr"},
                     {"text",  body}]})
    |> case do
      {:ok, %{status_code: 200, body: body}} -> {:ok, body}
      {:ok, %{status_code: _, body: body}}   -> {:error, body}
      {:error, error}                        -> {:error, error}
    end
  end

  def request(method, url, body \\ "", headers \\ [], options \\ []) do
    options = options ++ [hackney: [basic_auth: {"api", @apikey}]]
    super(method, url, body, headers, options)
  end

end
