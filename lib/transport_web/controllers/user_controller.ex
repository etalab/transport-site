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

  def add_badge_dataset(conn, %{"slug" => slug}) do
    slug
    |> Client.put_datasets({:add_tag, "GTFS"}, get_session(conn, :current_user)["apikey"])
    |> case do
      {:error, _} ->
        conn
        |> render("500.html")
      {:ok, _} ->
        conn
        |> render("add_badge_dataset.html")
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

end
