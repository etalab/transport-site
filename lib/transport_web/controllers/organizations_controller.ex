defmodule TransportWeb.OrganizationsController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client
  def search(conn, _) do
    render conn, "search_organizations.html"
  end

  def organization(conn, %{"slug" => slug}) do
    organization(conn, Client.organization(slug, :with_membership))
  end
  def organization(conn, {:ok, response}) do
    conn
    |> assign(:organization, response)
    |> assign(:is_member, is_member(response, conn))
    |> assign(:has_pending_membership, has_pending_membership(response, conn))
    |> assign(:has_refused_membership, has_refused_membership(response, conn))
    |> render("organization.html")
  end
  def organization(conn, {:error, _}) do
    conn
    |> render("500.html")
  end

  def claim(conn, %{"slug" => slug}) do
    if current_user(conn) == nil do
      conn
      |> put_flash(:error, gettext "connection_needed")
      |> organization(%{"slug" => slug})
    else
      conn
      |> claim(Client.organization(slug, :with_membership))
    end
  end
  def claim(conn, {:ok, response}) do
    cond do
    is_member(response, conn) ->
      conn
      |> put_flash(:error, gettext "already_organization_member")
      |> organization({:ok, response})
    has_pending_membership(response, conn) or has_refused_membership(response, conn) ->
      organization(conn,  {:ok, response})
    true ->
      case Client.request_organization_membership(response["slug"],
                                                  current_user(conn)["id"]) do
        {:ok, _} -> conn
                    |> put_flash(:info, "Your request will be handled")
                    |> organization(response)
        {:error, _} -> render "500.html"
      end
    end
  end
  def claim(conn, {:error, _}) do
    render conn, "500.html"
  end

  def is_member(organization, conn) do
    organization["members"]
    |> Enum.filter(fn member -> member["id"] == current_user(conn)["id"] end)
    |> Enum.empty?
    != true
  end

  def has_pending_membership(organization, conn) do
    has_status_membership(organization, conn, "pending")
  end

  def has_refused_membership(organization, conn) do
    has_status_membership(organization, conn, "refused")
  end

  def has_status_membership(organization, conn, status) do
    organization["membership"]
    |> Enum.filter(fn ms -> ms["user"]["id"] == current_user(conn)["id"]
                            and ms["status"] == status end)
    |> Enum.empty?
    != true
  end

  def current_user(conn) do
    get_session(conn, :current_user)
  end
end
