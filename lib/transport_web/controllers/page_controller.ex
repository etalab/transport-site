defmodule TransportWeb.PageController do
  use TransportWeb, :controller
  alias Transport.{Partner, Repo}
  import Ecto.Query

  def index(conn, _params) do
    render(
      conn,
      "index.html",
      %{:mailchimp_newsletter_url => :transport
                                     |> Application.get_all_env()
                                     |> Keyword.get(:mailchimp_newsletter_url)}
    )
  end

  def login(conn, %{"redirect_path" => redirect_path}) do
    conn
    |> put_session(:redirect_path, redirect_path)
    |> render("login.html")
  end

  def single_page(conn, %{"page" => "partners"} = params) do
    partners =
      Partner
      |> Repo.all()
      |> Task.async_stream(fn partner -> Map.put(partner, :description, Partner.description(partner)) end)
      |> Task.async_stream(fn {:ok, partner} -> Map.put(partner, :count_reuses, Partner.count_reuses(partner)) end)
      |> Stream.map(fn {ok, partner} -> partner end)
      |> Enum.to_list()

    conn
    |> assign(:partners, partners)
    |> assign(:page, "partners.html")
    |> render("single_page.html")
  end

  def single_page(conn, %{"page" => page}) do
    conn
    |> assign(:page, page <> ".html")
    |> render("single_page.html")
  end
end
