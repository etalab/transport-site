defmodule TransportWeb.SessionController do
  @moduledoc """
  Session management for transport.
  """

  use TransportWeb, :controller
  alias Datagouvfr.{Authentication, Client.User}
  require Logger

  def new(conn, _) do
    redirect(conn, external: Authentication.authorize_url!)
  end

  def create(conn, %{"code" => code}) do
    with %{token: token} <- Authentication.get_token!(code: code),
         conn <- conn
                 |> put_session(:token, token)
                 |> assign(:token, token),
         {:ok, user} <- User.me(conn)
    do
      conn
      |> put_session(:current_user, user_params(user))
      |> redirect(to: get_redirect_path(conn))
      |> halt()
    else
      {:error, error} ->
        Logger.error(error)
        conn
        |> put_flash(:error, dgettext("alert", "An error occured, please try again"))
        |> redirect(to: session_path(conn, :new))
        |> halt()
    end
  end

  def delete(conn, _) do
    conn
    |> configure_session(drop: true)
    |> redirect(to: page_path(conn, :index))
    |> halt()
  end

  #private functions

  defp user_params(%{} = user) do
    params =  Map.take(
      user,
      ["id", "apikey", "email", "first_name", "last_name", "avatar_thumbnail", "organizations"]
    )
    filtered_organizations = Enum.filter(Map.get(params, "organizations", []),
        fn org -> org["slug"] == "equipe-transport-data-gouv-fr" end)
    Map.put(params, "organizations", filtered_organizations)
  end

  defp get_redirect_path(conn) do
    case get_session(conn, :redirect_path) do
      nil -> "/"
      path -> path
    end
  end
end
