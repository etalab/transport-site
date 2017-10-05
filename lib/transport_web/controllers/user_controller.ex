defmodule TransportWeb.UserController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client
  plug :authentication_required

  def organizations(%Plug.Conn{} = conn, _) do
    conn
    |> get_session(:current_user)
    |> Client.me
    |> case do
     {:ok, response} ->
       conn
       |> assign(:has_organizations, Enum.empty?(response["organizations"]) == false)
       |> assign(:organizations, response["organizations"])
       |> render("organizations.html")
     {:error, _} -> conn |> render("500.html")
    end
  end

  def org_datasets(conn, %{"slug" => slug}) do
    slug
    |> Client.organizations(:with_datasets)
    |> case do
      {:error, _} ->
        conn
        |> render("500.html")
      {:ok, response} ->
        conn
        |> assign(:has_datasets, Enum.empty?(response["datasets"]) == false)
        |> assign(:datasets, response["datasets"])
        |> assign(:organization, response)
        |> render("org_datasets.html")
     end
  end

  defp authentication_required(conn, _) do
    conn
    |> get_session(:current_user)
    |> case  do
      nil ->
        conn
        |> put_flash(:info, gettext "connection_needed")
        |> redirect(to: page_path(conn, :login))
        |> halt()
      _ -> conn
    end
  end


  def org_datasets(conn, %{"slug" => slug}) do
    conn
    |> get_session(:current_user)
    |> org_datasets(conn, slug)
  end

  def org_datasets({:error, _}, conn, _) do
    conn
    |> render("500.html")
  end

  def org_datasets({:ok, response}, conn, _) do
    conn
    |> assign(:has_datasets, Enum.empty?(response["datasets"]) == false)
    |> assign(:datasets, response["datasets"])
    |> assign(:organization, response)
    |> render("org_datasets.html")
  end

  def org_datasets(nil, conn, _) do
    conn
    |> put_flash(:info, gettext "connection_needed")
    |> redirect(to: "/login/explanation")
  end

  def org_datasets(user, conn, slug) do
    slug
    |> Client.organizations(:with_datasets)
    |> org_datasets(conn, nil)
  end

end
