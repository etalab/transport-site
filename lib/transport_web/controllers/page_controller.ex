defmodule TransportWeb.PageController do
  require Logger
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client

  def index(conn, _params) do
    render conn, "index.html"
  end

  def login(conn, _) do
    render conn, "login.html"
  end

  def search_organizations(conn, _) do
    render conn, "search_organizations.html"
  end

  def organization(conn, %{"slug" => slug}) do
    organization(conn, Client.organization(slug))
  end
  def organization(conn, {:ok, response}) do
    conn
    |> assign(:organization, response)
    |> assign(:is_member, is_member(response, conn))
    |> render("organization.html")
  end
  def organization(conn, {:error, _}) do
    conn
    |> render("500.html")
  end

  def organization_claim(conn, %{"slug" => slug}) do
    if current_user(conn) == nil do
      conn
      |> put_flash(:error, gettext "connection_needed")
      |> organization(%{"slug" => slug})
    else
      conn
      |> organization_claim(Client.organization(slug))
    end
  end
  def organization_claim(conn, {:ok, response}) do
    if is_member(response, conn) do
      conn
      |> put_flash(:error, gettext "already_organization_member")
      |> organization({:ok, response})
    else
      Logger.info("add member")
      case Client.request_organization_membership(response["slug"],
                                                  current_user(conn)["id"]) do
        {:ok, _} -> conn
                    |> put_flash(:info, "Your request will be handled")
                    |> organization(response)
        {:error, _} -> render "500.html"
      end
    end
  end
  def organization_claim(conn, {:error, error}) do
    render conn, "500.html"
  end

  def is_member(organization, conn) do
    organization["members"]
    |> Enum.filter(fn member -> member["id"] == current_user(conn)["id"] end)
    |> Enum.empty?
    != true
  end

  def current_user(conn) do
    get_session(conn, :current_user)
  end

end
