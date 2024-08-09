defmodule TransportWeb.PageController do
  use TransportWeb, :controller
  alias DB.{AOM, Dataset, Region, Repo}
  alias Transport.CSVDocuments
  import Ecto.Query
  import TransportWeb.DatasetView, only: [icon_type_path: 1]
  import TransportWeb.Router.Helpers

  def index(conn, _params) do
    conn
    |> assign(:mailchimp_newsletter_url, Application.get_env(:transport, :mailchimp_newsletter_url))
    |> merge_assigns(home_index_stats())
    |> assign(:tiles, home_tiles(conn))
    |> put_breaking_news(DB.BreakingNews.get_breaking_news())
    |> render("index.html")
  end

  defp home_index_stats do
    # with HOTFIX for https://github.com/etalab/transport-site/issues/3609
    # combined with the fact our HTTP monitor checks the url every minute, should
    # allow regular traffic for most users
    temporary_ttl = :timer.minutes(15)
    Transport.Cache.fetch("home-index-stats", fn -> compute_home_index_stats() end, temporary_ttl)
  end

  defp put_breaking_news(conn, %{level: level, msg: msg}) do
    # The flash reason should match the view _breaking_news.html.heex
    conn |> put_flash(String.to_existing_atom("breaking_news_#{level}"), msg)
  end

  defp put_breaking_news(conn, %{}), do: conn

  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(ErrorView)
    |> render("404.html")
  end

  defp compute_home_index_stats do
    [
      count_by_type: Dataset.count_by_type(),
      count_train: Dataset.count_by_mode("rail"),
      count_boat: Dataset.count_by_mode("ferry"),
      count_coach: Dataset.count_coach(),
      count_regions: count_regions(),
      count_aoms: Repo.aggregate(AOM, :count, :id),
      count_aoms_with_dataset: count_aoms_with_dataset(),
      count_regions_completed: count_regions_completed(),
      count_public_transport_has_realtime: Dataset.count_public_transport_has_realtime(),
      count_paris2024: Dataset.count_by_custom_tag("paris2024"),
      percent_population: percent_population(),
      reusers: CSVDocuments.reusers(),
      facilitators: CSVDocuments.facilitators()
    ]
  end

  def login(conn, params) do
    conn
    |> put_session(:redirect_path, Map.get(params, "redirect_path", "/"))
    |> render("login.html")
  end

  defp single_page(conn, %{"page" => page}) do
    conn
    |> assign(:page, page <> ".html")
    |> render("single_page.html")
  end

  def accessibility(conn, _params) do
    single_page(conn, %{"page" => "accessibility"})
  end

  def missions(conn, _params) do
    single_page(conn, %{"page" => "missions"})
  end

  def loi_climat_resilience(conn, _params) do
    datasets_counts =
      DB.Dataset.base_query()
      |> DB.Dataset.filter_by_custom_tag("loi-climat-resilience")
      |> group_by([dataset: d], d.type)
      |> select([dataset: d], %{type: d.type, count: count(d.id)})
      |> order_by([dataset: d], desc: count(d.id))
      |> DB.Repo.all()

    conn
    |> assign(:tiles, Enum.map(datasets_counts, &climate_resilience_bill_type_tile(conn, &1)))
    |> assign(:page, "loi_climat_resilience.html")
    |> render("loi_climat_resilience.html")
  end

  def infos_producteurs(conn, _params) do
    conn
    |> assign(:mailchimp_newsletter_url, Application.get_env(:transport, :mailchimp_newsletter_url))
    |> render("infos_producteurs.html")
  end

  def infos_reutilisateurs(%Plug.Conn{} = conn, _params), do: render(conn, "infos_reutilisateurs.html")

  def robots_txt(%Plug.Conn{} = conn, _params) do
    # See http://www.robotstxt.org/robotstxt.html
    # for documentation on how to use the robots.txt file
    app_env = Application.fetch_env!(:transport, :app_env)
    text(conn, robots_txt_content(app_env))
  end

  def robots_txt_content(:staging = _app_env) do
    """
    User-agent: *
    Disallow: /
    """
  end

  def robots_txt_content(_app_env) do
    """
    User-agent: *
    Allow: /
    Disallow: /backoffice/
    Disallow: /validation/*
    Disallow: /login/*
    Disallow: /resources/conversions/*
    """
  end

  def security_txt(conn, _params) do
    expires = DateTime.utc_now() |> DateTime.add(1 * 24 * 3600 * 7, :second) |> DateTime.to_iso8601()

    content = """
    Contact: mailto:#{Application.fetch_env!(:transport, :security_email)}
    Preferred-Languages: fr, en
    Expires: #{expires}
    """

    conn |> text(content)
  end

  def humans_txt(conn, _params) do
    http_client = Transport.Shared.Wrapper.HTTPoison.impl()

    authors =
      case http_client.get!("https://beta.gouv.fr/api/v2.5/authors.json") do
        %HTTPoison.Response{status_code: 200, body: body} -> body |> Jason.decode!()
        _ -> %{}
      end

    content =
      case http_client.get!("https://beta.gouv.fr/api/v2.5/startups_details.json") do
        %HTTPoison.Response{status_code: 200, body: body} ->
          transport_details = body |> Jason.decode!() |> Map.fetch!("transport")
          humans_txt_build_content(authors, transport_details)

        _ ->
          ""
      end

    conn |> text(content)
  end

  defp humans_txt_build_content(authors, transport_details) do
    authors = authors |> Enum.into(%{}, fn %{"id" => id} = data -> {id, data} end)
    author_fullname = fn member_id -> get_in(authors, [member_id, "fullname"]) end

    active_members =
      transport_details |> Map.get("active_members", []) |> Enum.map(&author_fullname.(&1)) |> Enum.sort()

    previous_members =
      transport_details
      |> Map.take(["previous_members", "expired_members"])
      |> Map.values()
      |> List.flatten()
      |> Enum.map(&author_fullname.(&1))
      |> Enum.sort()

    ["# Membres actuels", active_members, "", "# Anciens membres", previous_members]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  def espace_producteur(%Plug.Conn{} = conn, _params) do
    {conn, datasets} =
      case DB.Dataset.datasets_for_user(conn) do
        datasets when is_list(datasets) ->
          {conn, datasets}

        {:error, _} ->
          conn = conn |> put_flash(:error, dgettext("alert", "Unable to get all your resources for the moment"))
          {conn, []}
      end

    last_year = Date.utc_today().year - 1

    conn
    |> assign(:datasets, datasets)
    |> assign(:downloads_reference_year, last_year)
    |> assign(:downloads_last_year, DB.DatasetMonthlyMetric.downloads_for_year(datasets, last_year))
    |> TransportWeb.Session.set_is_producer(datasets)
    |> render("espace_producteur.html")
  end

  defp aoms_with_dataset do
    aoms_legal_owners =
      Dataset.base_query()
      |> join(:inner, [dataset: d], a in assoc(d, :legal_owners_aom), as: :aom)
      |> select([aom: a], a.id)

    aoms_datasets = Dataset.base_query() |> where([dataset: d], not is_nil(d.aom_id)) |> select([dataset: d], d.aom_id)

    from(a in AOM, where: a.id in subquery(union(aoms_legal_owners, ^aoms_datasets)))
  end

  defp count_aoms_with_dataset, do: Repo.aggregate(aoms_with_dataset(), :count, :id)

  defp population_with_dataset, do: Repo.aggregate(aoms_with_dataset(), :sum, :population) || 0

  defp population_totale, do: Repo.aggregate(AOM, :sum, :population)

  defp percent_population, do: percent(population_with_dataset(), population_totale())

  defp percent(_a, 0), do: 0
  defp percent(_a, nil), do: 0
  defp percent(a, b), do: Float.round(a / b * 100, 1)

  defp count_regions do
    Region |> where([r], r.nom != "National") |> select([r], count(r.id)) |> Repo.one!()
  end

  defp count_regions_completed do
    Region |> where([r], r.is_completed == true) |> Repo.aggregate(:count, :id)
  end

  defmodule Tile do
    @enforce_keys [:link, :icon, :title, :count]
    defstruct [:link, :icon, :title, :count, :type, :documentation_url]
  end

  def home_tiles(conn) do
    counts = home_index_stats()

    [
      type_tile(conn, "public-transit"),
      %Tile{
        link: dataset_path(conn, :index, type: "public-transit", filter: "has_realtime"),
        icon: icon_type_path("real-time-public-transit"),
        title: dgettext("page-index", "Public transport - realtime traffic"),
        count: Keyword.fetch!(counts, :count_public_transport_has_realtime)
      },
      %Tile{
        # 14 is the region « National » We defined coaches as buses not bound to a region or AOM
        link: dataset_path(conn, :by_region, 14, "modes[]": "bus"),
        icon: icon_type_path("long-distance-coach"),
        title: dgettext("page-index", "Long distance coach"),
        count: Keyword.fetch!(counts, :count_coach)
      },
      %Tile{
        link: dataset_path(conn, :index, "modes[]": "rail"),
        icon: icon_type_path("train"),
        title: dgettext("page-index", "Rail transport"),
        count: Keyword.fetch!(counts, :count_train)
      },
      %Tile{
        link: dataset_path(conn, :index, "modes[]": "ferry"),
        icon: icon_type_path("boat"),
        title: dgettext("page-index", "Sea and river transport"),
        count: Keyword.fetch!(counts, :count_boat)
      },
      type_tile(conn, "air-transport"),
      type_tile(conn, "bike-scooter-sharing"),
      type_tile(conn, "car-motorbike-sharing"),
      type_tile(conn, "bike-way"),
      type_tile(conn, "bike-parking"),
      type_tile(conn, "transport-traffic",
        documentation_url: "https://doc.transport.data.gouv.fr/producteurs/comptage-des-mobilites"
      ),
      type_tile(conn, "road-data"),
      type_tile(conn, "low-emission-zones"),
      type_tile(conn, "carpooling-areas"),
      type_tile(conn, "carpooling-lines"),
      type_tile(conn, "carpooling-offers"),
      type_tile(conn, "charging-stations"),
      type_tile(conn, "private-parking"),
      type_tile(conn, "locations"),
      type_tile(conn, "informations"),
      %Tile{
        link: dataset_path(conn, :index, %{"custom_tag" => "paris2024"}),
        icon: icon_type_path("paris2024"),
        title: "JOP Paris 2024",
        count: Keyword.fetch!(counts, :count_paris2024)
      }
    ]
  end

  defp climate_resilience_bill_type_tile(%Plug.Conn{} = conn, %{count: count, type: type}) do
    %Tile{
      type: type,
      link: dataset_path(conn, :index, type: type, "loi-climat-resilience": true),
      icon: icon_type_path(type),
      title: DB.Dataset.type_to_str(type),
      count: count
    }
  end

  defp type_tile(conn, type, options \\ []) do
    %Tile{
      type: type,
      link: dataset_path(conn, :index, type: type),
      icon: icon_type_path(type),
      title: DB.Dataset.type_to_str(type),
      count: Keyword.fetch!(home_index_stats(), :count_by_type)[type],
      documentation_url: Keyword.get(options, :documentation_url)
    }
  end
end
