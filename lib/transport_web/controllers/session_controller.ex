defmodule TransportWeb.SessionController do
  @moduledoc """
  Session management for transport.
  """

  use TransportWeb, :controller
  alias Transport.Datagouvfr.Authentication
  alias OAuth2.Client

  @user_fields "avatar,avatar_thumbnail,first_name,id,last_name,page,slug,uri,apikey,email"
  @user_endpoint "/api/1/me/"

  def new(conn, _) do
    redirect conn, external: authorize_url!()
  end

  def create(conn, %{"code" => code}) do
    client = get_token!(code)
    user   = get_user!(client)

    conn
    |> put_session(:current_user, user)
    |> put_session(:access_token, client.token.access_token)
    |> redirect(to: user_path(conn, :organizations))
    |> halt()
  end

  def delete(conn, _) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: page_path(conn, :index))
    |> halt()
  end

  # private

  defp authorize_url! do
    Authentication.authorize_url!
  end

  defp get_token!(code) do
    Authentication.get_token!(code: code)
  end

  defp get_user!(client) do
    client
    |> Client.put_header("x-fields", @user_fields)
    |> Client.get!(@user_endpoint)
    |> Map.get(:body)
  end
end
