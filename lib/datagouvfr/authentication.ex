defmodule Datagouvfr.Authentication do
  @moduledoc """
  An OAuth2 strategy for data.gouv.fr.
  """

  alias OAuth2.Client
  use OAuth2.Strategy
  alias OAuth2.Strategy.AuthCode

  # Public API

  def client(token \\ nil) do
    :oauth2
    |> Application.get_env(__MODULE__)
    |> Keyword.put(:token, token)
    |> Client.new()
  end

  def authorize_url! do
    Client.authorize_url!(client(), %{scope: "default"})
  end

  def get_token!(params \\ []) do
    Client.get_token!(client(), params, [], [{:timeout, 15_000}])
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
