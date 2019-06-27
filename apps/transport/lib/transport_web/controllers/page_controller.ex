defmodule TransportWeb.PageController do
  use TransportWeb, :controller
  alias Transport.{AOM, Dataset, Partner, RealTimeProviders, Region, Repo}
  import Ecto.Query

  def index(conn, _params) do
    conn
    |> assign(:mailchimp_newsletter_url, Application.get_env(:transport, :mailchimp_newsletter_url))
    |> assign(:count_by_type, Dataset.count_by_type())
    |> assign(:count_aoms_with_dataset, count_aoms_with_dataset())
    |> assign(:count_regions_completed, count_regions_completed())
    |> assign(:count_has_realtime, Dataset.count_has_realtime())
    |> assign(:percent_population, percent_population())
    |> render("index.html")
  end

  def login(conn, %{"redirect_path" => redirect_path}) do
    conn
    |> put_session(:redirect_path, redirect_path)
    |> render("login.html")
  end

  def single_page(conn, %{"page" => "partners"}) do
    partners =
      Partner
      |> Repo.all()
      |> Task.async_stream(fn partner -> Map.put(partner, :description, Partner.description(partner)) end)
      |> Task.async_stream(fn {:ok, partner} -> Map.put(partner, :count_reuses, Partner.count_reuses(partner)) end)
      |> Stream.map(fn {:ok, partner} -> partner end)
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

  def real_time(conn, _params) do
    conn
    |> assign(:providers, RealTimeProviders.value())
    |> single_page(%{"page" => "real_time"})
  end

  defp aoms_with_dataset do
    from a in AOM,
      join: d in Dataset,
      on: a.id == d.aom_id or not is_nil(a.parent_dataset_id),
      distinct: a.id
  end

  defp count_aoms_with_dataset, do: Repo.aggregate(aoms_with_dataset(), :count, :id)

  defp population_with_dataset, do: Repo.aggregate(aoms_with_dataset(), :sum, :population_totale_2014)

  defp population_totale, do: Repo.aggregate(AOM, :sum, :population_totale_2014)

  defp percent_population, do: percent(population_with_dataset(), population_totale())

  defp percent(_a, 0), do: 0
  defp percent(_a, nil), do: 0
  defp percent(a, b), do: Float.round((a / b) * 100, 1)

  defp count_regions_completed do
    Region
    |> where([r], r.is_completed == true)
    |> Repo.aggregate(:count, :id)
  end
end
