defmodule TransportWeb.UserController do
  use TransportWeb, :controller
  alias Transport.Datagouvfr.Client.{Organizations, User, Datasets}
  alias Transport.DataValidator.Server
  alias TransportWeb.ErrorView

  def organizations(%Plug.Conn{} = conn, _) do
    conn
    |> User.me
    |> case do
     {:ok, response} ->
       conn
       |> assign(:organizations, response["organizations"])
       |> render("organizations.html")
     {:error, error} ->
       IO.puts(error)
       conn
       |> put_status(:internal_server_error)
       |> render(ErrorView, "500.html")
    end
  end

  def organization_datasets(conn, %{"slug" => slug}) do
    conn
    |> Organizations.get(slug, :with_datasets)
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
    conn
    |> Datasets.put(slug, {:add_tag, "GTFS"})
    |> case do
      {:ok, dataset} ->
        Server.validate_data(List.first(dataset["resources"])["url"])
        conn
        |> render("add_badge_dataset.html")
      {:error, _} ->
        conn
        |> put_status(:internal_server_error)
        |> render(ErrorView, "500.html")
     end
  end
end
