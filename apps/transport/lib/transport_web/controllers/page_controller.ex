defmodule TransportWeb.PageController do
  use TransportWeb, :controller
  alias DB.{AOM, Dataset, Region, Repo}
  alias Transport.CachedFiles
  import Ecto.Query
  import TransportWeb.DatasetView, only: [icon_type_path: 1]
  import TransportWeb.Router.Helpers

  def index(conn, _params) do
    conn
    |> merge_assigns(home_index_stats())
    |> assign(:tiles, home_tiles(conn) |> Enum.map(&patch_vls_tiles/1))
    |> put_breaking_news(DB.BreakingNews.get_breaking_news())
    |> render("index.html")
  end

  defp home_index_stats do
    # with HOTFIX for https://github.com/etalab/transport-site/issues/3609
    # combined with the fact our HTTP monitor checks the url every minute, should
    # allow regular traffic for most users
    Transport.Cache.fetch(
      "home-index-stats",
      fn -> compute_home_index_stats() end,
      Transport.PreemptiveHomeStatsCache.cache_ttl()
    )
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

  def compute_home_index_stats do
    [
      count_by_type: Dataset.count_by_type(),
      count_regions: count_regions(),
      count_aoms: Repo.aggregate(AOM, :count, :id),
      count_aoms_with_dataset: count_aoms_with_dataset(),
      count_regions_completed: count_regions_completed(),
      percent_population: percent_population(),
      facilitators: CachedFiles.facilitators()
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

  def infos_producteurs(conn, _params) do
    conn |> render("infos_producteurs.html")
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
    Sitemap: #{page_url(TransportWeb.Endpoint, :sitemap_txt)}
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

  def sitemap_txt(%Plug.Conn{} = conn, _params) do
    urls =
      Transport.Cache.fetch(
        "sitemap_txt_urls",
        fn ->
          dataset_types = DB.Dataset.types()
          dataset_slugs = DB.Dataset.base_query() |> select([dataset: d], d.slug) |> DB.Repo.all()
          region_insees = DB.Region |> select([r], r.insee) |> where([r], not is_nil(r.insee)) |> DB.Repo.all()
          departement_insees = DB.Departement |> select([r], r.insee) |> DB.Repo.all()
          epci_insees = DB.EPCI |> select([a], a.insee) |> DB.Repo.all()
          commune_insees = DB.Commune |> select([c], c.insee) |> DB.Repo.all()

          [
            page_url(conn, :index),
            page_url(conn, :missions),
            page_url(conn, :accessibility),
            page_url(conn, :infos_producteurs),
            page_url(conn, :infos_reutilisateurs),
            page_url(conn, :robots_txt),
            page_url(conn, :security_txt),
            page_url(conn, :humans_txt),
            page_url(conn, :espace_producteur),
            reuser_space_url(conn, :espace_reutilisateur),
            reuse_url(conn, :index),
            stats_url(conn, :index),
            explore_url(conn, :vehicle_positions),
            explore_url(conn, :gtfs_stops),
            session_url(conn, :new),
            landing_pages_url(conn, :vls),
            live_url(conn, TransportWeb.Live.OnDemandValidationSelectLive),
            live_url(conn, TransportWeb.Live.GTFSDiffSelectLive),
            live_url(conn, TransportWeb.Live.SIRIQuerierLive),
            dataset_url(conn, :index)
          ] ++
            Enum.map(dataset_types, &dataset_url(conn, :index, type: &1)) ++
            Enum.map(dataset_slugs, &dataset_url(conn, :details, &1)) ++
            Enum.map(region_insees, &dataset_url(conn, :by_region, &1)) ++
            Enum.map(departement_insees, &dataset_url(conn, :by_departement_insee, &1)) ++
            Enum.map(epci_insees, &dataset_url(conn, :by_epci, &1)) ++
            Enum.map(commune_insees, &dataset_url(conn, :by_commune_insee, &1))
        end,
        :timer.hours(1)
      )

    conn |> text(Enum.join(urls, "\n"))
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
      |> Enum.dedup()

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

    from(a in AOM, where: a.id in subquery(aoms_legal_owners))
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
    [
      type_tile(conn, "public-transit"),
      type_tile(conn, "vehicles-sharing"),
      type_tile(conn, "bike-data"),
      type_tile(conn, "road-data"),
      type_tile(conn, "carpooling-areas"),
      type_tile(conn, "carpooling-lines"),
      type_tile(conn, "carpooling-offers"),
      type_tile(conn, "charging-stations"),
      type_tile(conn, "informations"),
      type_tile(conn, "pedestrian-path")
    ]
  end

  defp patch_vls_tiles(%Tile{type: "vehicles-sharing"} = tile) do
    %{tile | link: "/landing-vls"}
  end

  defp patch_vls_tiles(tile), do: tile

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
