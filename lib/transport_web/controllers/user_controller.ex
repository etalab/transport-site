defmodule TransportWeb.UserController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client

  # Entry by the router
  def organizations(%Plug.Conn{} = conn, _) do
    conn
    |> get_session(:current_user)
    |> organizations(conn)
  end

  # I'm not logged in, the first parameter is null
  def organizations(nil, conn) do
    conn
    |> put_flash(:info, gettext "connection_needed")
    |> redirect(to: "/login/explanation")
  end

  # There was an error when requesting datagouvfr API
  def organizations({:error, _}, conn) do
    conn
    |> render("500.html")
  end

  #Everything is ok, I can act normally
  def organizations({:ok, response}, conn) do
    conn
    |> assign(:has_organizations, Enum.empty?(response["organizations"]) == false)
    |> assign(:organizations, response["organizations"])
    |> render("organizations.html")
  end

  #I'm logged in, the first param is a user
  def organizations(user, conn) when is_map(user) do
    %{:apikey => user["apikey"]}
    |> Client.me
    |> organizations(conn)
  end

end
