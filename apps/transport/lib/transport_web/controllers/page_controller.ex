defmodule TransportWeb.PageController do
  use TransportWeb, :controller
  alias DB.{AOM, Dataset, Region, Repo}
  alias Transport.CachedFiles
  import Ecto.Query
  import TransportWeb.DatasetView, only: [icon_type_path: 1]

  def index(conn, _params) do
    conn
    |> merge_assigns(home_index_stats())
    |> assign(:tiles, home_tiles() |> Enum.map(&patch_vls_tiles/1))
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
      count_transport_offers: count_transport_offers(),
      percent_population: percent_population(),
      facilitators: CachedFiles.facilitators()
    ]
  end

  def login(conn, params) do
    conn
    |> put_session(:redirect_path, Map.get(params, "redirect_path", ~p"/"))
    |> render("login.html")
  end

  defp single_page(conn, %{"content" => content, "menu" => menu}) do
    conn
    |> assign(:content, content)
    |> assign(:menu_items, menu)
    |> render("single_page.html")
  end

  defp single_page(conn, %{"page" => page}) do
    conn
    |> assign(:content, nil)
    |> assign(:menu_items, nil)
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

  def nouveautes(conn, _params) do
    markdown = File.read!(__DIR__ <> "/../templates/page/nouveautes.html.md")
    content = TransportWeb.MarkdownHandler.to_html_with_anchors(markdown)
    menu_title = content |> Floki.parse_document!() |> Floki.find("h1") |> Floki.text() |> String.replace("# ", "")

    conn
    |> assign(:page_title, dgettext("page-nouveautes", "New features"))
    |> assign(:menu_title, menu_title)
    |> single_page(%{"content" => content, "menu" => generate_menu(content)})
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
    Sitemap: #{url(~p"/sitemap.txt")}
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
            url(~p"/"),
            url(~p"/missions"),
            url(~p"/nouveautes"),
            url(~p"/accessibilite"),
            url(~p"/infos_producteurs"),
            url(~p"/infos_reutilisateurs"),
            url(~p"/robots.txt"),
            url(~p"/.well-known/security.txt"),
            url(~p"/humans.txt"),
            url(~p"/espace_producteur"),
            url(~p"/espace_reutilisateur"),
            url(~p"/reuses"),
            url(~p"/stats"),
            url(~p"/explore/vehicle-positions"),
            url(~p"/explore/gtfs-stops"),
            url(~p"/login"),
            url(~p"/landing-vls"),
            url(~p"/validation"),
            url(~p"/tools/gtfs_diff"),
            url(~p"/tools/siri-querier"),
            url(~p"/datasets")
          ] ++
            Enum.map(dataset_types, &url(~p"/datasets?#{[type: &1]}")) ++
            Enum.map(dataset_slugs, &url(~p"/datasets/#{&1}")) ++
            Enum.map(region_insees, &url(~p"/datasets/region/#{&1}")) ++
            Enum.map(departement_insees, &url(~p"/datasets/departement/#{&1}")) ++
            Enum.map(epci_insees, &url(~p"/datasets/epci/#{&1}")) ++
            Enum.map(commune_insees, &url(~p"/datasets/commune/#{&1}"))
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

  defmodule Tile do
    @enforce_keys [:link, :icon, :title, :count]
    defstruct [:link, :icon, :title, :count, :type, :documentation_url]
  end

  @doc """
  Build the tiles displayed on the home page.
  The home tile structs are also used on every dataset listing page to find the title of the page:
  the URL params are matched againgt home page tiles "link"s,
  and when there is a match the "title" of the tile is used to set the dataset listing page title.
  """

  def home_tiles do
    # Fetch stats once here to avoid multiple cache fetch that puts noise in logs
    stats = home_index_stats()

    [
      type_tile(stats, "public-transit"),
      type_tile(stats, "vehicles-sharing"),
      type_tile(stats, "bike-data"),
      type_tile(stats, "road-data"),
      type_tile(stats, "carpooling-areas"),
      type_tile(stats, "carpooling-lines"),
      type_tile(stats, "carpooling-offers"),
      type_tile(stats, "charging-stations"),
      type_tile(stats, "informations"),
      type_tile(stats, "pedestrian-path")
    ]
  end

  defp patch_vls_tiles(%Tile{type: "vehicles-sharing"} = tile) do
    %{tile | link: ~p"/landing-vls"}
  end

  defp patch_vls_tiles(tile), do: tile

  defp type_tile(stats, type, options \\ []) do
    %Tile{
      type: type,
      link: ~p"/datasets?#{[type: type]}",
      icon: icon_type_path(type),
      title: DB.Dataset.type_to_str(type),
      count: Keyword.fetch!(stats, :count_by_type)[type],
      documentation_url: Keyword.get(options, :documentation_url)
    }
  end

  defp count_transport_offers do
    DB.Dataset.base_query()
    |> join(:inner, [dataset: d], o in assoc(d, :offers), as: :offer)
    |> select([offer: o], count(o.id, :distinct))
    |> DB.Repo.one!()
  end

  defp generate_menu(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("h2, h3, h4")
    |> Enum.reduce([], &accumulate_tags/2)
    |> Enum.reverse()
  end

  defp accumulate_tags({tag, _attrs, children} = node, acc) do
    id = Floki.attribute(node, "id")
    text = Floki.text(children) |> String.trim_leading("# \n")

    case tag do
      "h2" ->
        # Start a new H2 block with an empty list for sub-items
        [%{title: text, id: id, sub_items: []} | acc]

      # h3 or h4
      _sub ->
        case acc do
          [current_h2 | rest] ->
            # Add this sub-heading to the most recent H2
            updated_h2 = %{current_h2 | sub_items: current_h2.sub_items ++ [%{title: text, id: id}]}
            [updated_h2 | rest]

          [] ->
            # Handle case where h3/h4 appears before any h2
            acc
        end
    end
  end
end
