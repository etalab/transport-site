defmodule Datagouvfr.Authentication.Wrapper do
  @moduledoc """
  An Authentication wrapper, useful for testing purposes
  """
  @callback get_token!(keyword() | map()) :: map()

  def impl, do: Application.get_env(:datagouvfr, :authentication_impl)
end

defmodule Datagouvfr.Authentication.Dummy do
  @moduledoc """
  A dummy Authentication module, giving back a dummy tocken.
  """
  @behaviour Datagouvfr.Authentication.Wrapper

  @impl Datagouvfr.Authentication.Wrapper
  def get_token!(_), do: %{token: "token"}
end

defmodule Datagouvfr.Authentication do
  @moduledoc """
  An OAuth2 strategy for data.gouv.fr.
  """

  alias OAuth2.Client
  use OAuth2.Strategy
  alias OAuth2.Strategy.AuthCode
  @behaviour Datagouvfr.Authentication.Wrapper

  # Public API

  @spec client(any) :: OAuth2.Client.t()
  def client(token \\ nil) do
    :oauth2
    |> Application.get_env(__MODULE__)
    |> Keyword.put(:token, token)
    |> Client.new()
    |> Client.put_serializer("application/json", Jason)
  end

  @spec authorize_url :: binary()
  def authorize_url do
    {_, url} = Client.authorize_url(client(), scope: "default")
    url
  end

  @impl Datagouvfr.Authentication.Wrapper
  @spec get_token!(keyword() | map()) :: OAuth2.Client.t()
  def get_token!(params \\ []) do
    Client.get_token!(client(), params, [], [{:timeout, 15_000}])
  end

  # Strategy Callbacks

  @impl OAuth2.Strategy
  @spec authorize_url(OAuth2.Client.t(), keyword() | map()) :: OAuth2.Client.t()
  def authorize_url(client, params) do
    AuthCode.authorize_url(client, params)
  end

  @impl OAuth2.Strategy
  @spec get_token(OAuth2.Client.t(), keyword(), [{binary(), binary()}]) :: OAuth2.Client.t()
  def get_token(client, params, headers) do
    client
    |> put_param("client_secret", client.client_secret)
    |> put_param("grant_type", "client_credentials")
    |> put_header("accept", "application/json")
    |> AuthCode.get_token(params, headers)
  end
end
