defmodule TransportWeb.UserController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client
  alias TransportWeb.ErrorView

  def organizations(%Plug.Conn{} = conn, _) do
    conn
    |> Client.me
    |> case do
     {:ok, response} ->
       conn
       |> assign(:organizations, response["organizations"])
       |> render("organizations.html")
     {:error, _} ->
       conn
       |> put_status(:internal_server_error)
       |> render(ErrorView, "500.html")
    end
  end

  def organization_datasets(conn, %{"slug" => slug}) do
    slug
    |> Client.organizations(:with_datasets)
    |> case do
      {:ok, response} ->
        conn
        |> assign(:has_datasets, Enum.empty?(response["datasets"]) == false)
        |> assign(:datasets, response["datasets"])
        |> assign(:organization, response)
        |> render("organization_datasets.html")
     {:error, _} ->
       conn
       |> put_status(:internal_server_error)
       |> render(ErrorView, "500.html")
     end
  end

  def add_badge_dataset(conn, %{"slug" => slug}) do
    slug
    |> Client.put_datasets({:add_tag, "GTFS"}, conn)
    |> case do
      {:ok, _} ->
        conn
        |> render("add_badge_dataset.html")
      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "500.html")
     end
  end
end
