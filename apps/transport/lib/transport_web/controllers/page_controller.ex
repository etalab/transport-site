defmodule TransportWeb.PageController do
  use TransportWeb, :controller
  alias DB.{AOM, Dataset, Partner, Region, Repo}
  alias Transport.CSVDocuments
  import Ecto.Query

  def index(conn, _params) do
    conn
    |> assign(:mailchimp_newsletter_url, Application.get_env(:transport, :mailchimp_newsletter_url))
    |> assign(:count_by_type, Dataset.count_by_type())
    |> assign(:count_train, Dataset.count_by_mode("rail"))
    |> assign(:count_boat, Dataset.count_by_mode("ferry"))
    |> assign(:count_coach, Dataset.count_coach())
    |> assign(:count_aoms_with_dataset, count_aoms_with_dataset())
    |> assign(:count_regions_completed, count_regions_completed())
    |> assign(:count_public_transport_has_realtime, Dataset.count_public_transport_has_realtime())
    |> assign(:percent_population, percent_population())
    |> assign(:reusers, CSVDocuments.reusers())
    |> render("index.html")
  end

  def login(conn, %{"redirect_path" => redirect_path}) do
    conn
    |> put_session(:redirect_path, redirect_path)
    |> render("login.html")
  end

  def partners(conn) do
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

  defp single_page(conn, %{"page" => page}) do
    conn
    |> assign(:page, page <> ".html")
    |> render("single_page.html")
  end

  def real_time(conn, _params) do
    conn
    |> assign(:providers, CSVDocuments.real_time_providers())
    |> single_page(%{"page" => "real_time"})
  end

  def conditions(conn, _params) do
    single_page(conn, %{"page" => "conditions"})
  end

  def producteurs(conn, _params) do
    conn
    |> assign(:mailchimp_newsletter_url, Application.get_env(:transport, :mailchimp_newsletter_url))
    |> render("producteurs.html")
  end

  @doc """
    Retrieve the user datasets + corresponding org datasets.

    Data Gouv is queried, and we support a degraded mode with an error reporting in case of connection issue.
  """
  def espace_producteur(conn, _params) do
    {datasets, errors} =
      [
        Dataset.user_datasets(conn),
        Dataset.user_org_datasets(conn)
      ]
      |> Enum.split_with(&(elem(&1, 0) == :ok))

    datasets =
      datasets
      |> Enum.map(&elem(&1, 1))
      |> List.flatten()

    errors
    |> Enum.each(&Sentry.capture_exception(&1))

    # NOTE: this could be refactored in more functional style, but that will be good enough for today
    conn =
      if length(errors) != 0 do
        conn |> put_flash(:error, dgettext("alert", "Unable to get all your resources for the moment"))
      else
        conn
      end

    conn
    |> assign(:datasets, datasets)
    |> render("espace_producteur.html")
  end

  defp aoms_with_dataset do
    from(a in AOM,
      join: d in Dataset,
      on: a.id == d.aom_id or not is_nil(a.parent_dataset_id),
      distinct: a.id
    )
  end

  defp count_aoms_with_dataset, do: Repo.aggregate(aoms_with_dataset(), :count, :id)

  defp population_with_dataset, do: Repo.aggregate(aoms_with_dataset(), :sum, :population_totale_2014)

  defp population_totale, do: Repo.aggregate(AOM, :sum, :population_totale_2014)

  defp percent_population, do: percent(population_with_dataset(), population_totale())

  defp percent(_a, 0), do: 0
  defp percent(_a, nil), do: 0
  defp percent(a, b), do: Float.round(a / b * 100, 1)

  defp count_regions_completed do
    Region
    |> where([r], r.is_completed == true)
    |> Repo.aggregate(:count, :id)
  end
end
