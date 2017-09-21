defmodule Transport.OAuth2.Strategy.Datagouvfr do
  @moduledoc """
  An OAuth2 strategy for data.gouv.fr.
  """
  use OAuth2.Strategy
  alias OAuth2.Strategy.AuthCode
  alias OAuth2.Client

  # Public API

  def client do
    :oauth2
    |> Application.get_env(__MODULE__)
    |> Client.new()
  end

  def authorize_url! do
    Client.authorize_url!(client(), %{scope: "default"})
  end

  def get_token!(params \\ []) do
    Client.get_token!(client(), params)
  end

  # Strategy Callbacks

  def authorize_url(client, params) do
    AuthCode.authorize_url(client, params)
  end

  def get_token(client, params, headers) do
    client
    |> put_param("client_secret", client.client_secret)
    |> put_param("grant_type", "client_credentials")
    |> put_header("accept", "application/json")
    |> AuthCode.get_token(params, headers)
  end
end
