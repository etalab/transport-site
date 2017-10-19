defmodule Transport.Datagouvfr.Authentication do
  @moduledoc """
  An OAuth2 strategy for data.gouv.fr.
  """

  use OAuth2.Strategy
  alias OAuth2.Strategy.AuthCode
  alias OAuth2.Client

  # Public API

  def client(token \\ nil) do
    :oauth2
    |> Application.get_env(__MODULE__)
    |> Keyword.put(:token, token)
    |> Client.new()
  end

  def authorize_url! do
    client() |> Client.authorize_url!(%{scope: "default"})
  end

  def get_token!(params \\ []) do
    client() |> Client.get_token!(params)
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    client |> AuthCode.authorize_url(params)
  end

  def get_token(client, params, headers) do
    client
    |> put_param("client_secret", client.client_secret)
    |> put_param("grant_type", "client_credentials")
    |> put_header("accept", "application/json")
    |> AuthCode.get_token(params, headers)
  end
end
