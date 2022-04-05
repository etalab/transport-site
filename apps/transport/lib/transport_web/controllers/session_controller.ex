defmodule TransportWeb.SessionController do
  @moduledoc """
  Session management for transport.
  """

  use TransportWeb, :controller
  alias Datagouvfr.Authentication
  require Logger

  def new(conn, _) do
    redirect(conn, external: Authentication.authorize_url())
  end

  def create(conn, %{"code" => code}) do
    authentication_module = Datagouvfr.Authentication.Wrapper.impl()
    user_module = Datagouvfr.Client.User.Wrapper.impl()

    with %{token: token} <- authentication_module.get_token!(code: code),
         conn <-
           conn
           |> put_session(:token, token)
           |> assign(:token, token),
         {:ok, user} <- user_module.me(conn) do
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

  def create(conn, %{"error" => error, "error_description" => description}) do
    Logger.error("error while creating the session: #{error} - #{description}")

    conn
    |> put_flash(:error, dgettext("alert", "An error occured, please try again"))
    |> redirect(to: session_path(conn, :new))
    |> halt()
  end

  def delete(conn, _) do
    redirect_path =
      case conn.params["redirect_path"] do
        nil ->
          page_path(conn, :index)

        path ->
          path
      end

    conn
    |> configure_session(drop: true)
    |> redirect(to: redirect_path)
    |> halt()
  end

  # private functions

  defp user_params(%{} = user) do
    params =
      Map.take(
        user,
        ["id", "apikey", "email", "first_name", "last_name", "avatar_thumbnail", "organizations"]
      )

    filtered_organizations =
      Enum.filter(
        Map.get(params, "organizations", []),
        fn org -> org["slug"] == "equipe-transport-data-gouv-fr" end
      )

    Map.put(params, "organizations", filtered_organizations)
  end

  defp get_redirect_path(conn) do
    case get_session(conn, :redirect_path) do
      nil -> "/"
      path -> path
    end
  end
end
