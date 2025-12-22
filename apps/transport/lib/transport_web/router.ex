defmodule TransportWeb.Router do
  use TransportWeb, :router
  use Sentry.PlugCapture
  import Phoenix.LiveDashboard.Router

  defimpl Plug.Exception, for: Phoenix.Template.UndefinedError do
    def status(_exception), do: 404
    def actions(e), do: [%{label: "Not found", handler: {IO, :puts, ["Template not found: #{inspect(e)}"]}}]
  end

  pipeline :browser_no_csp do
    plug(:canonical_host)
    plug(TransportWeb.Plugs.RateLimiter, :use_env_variables)
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_flash)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(TransportWeb.Plugs.PutLocale)
    plug(:assign_current_user)
    plug(:assign_datagouv_token)
    plug(:maybe_login_again)
    plug(:assign_mix_env)
    plug(Sentry.PlugContext)
  end

  pipeline :browser do
    plug(:browser_no_csp)
    plug(TransportWeb.Plugs.CustomSecureBrowserHeaders)
  end

  pipeline :accept_json do
    plug(:accepts, ["json"])
  end

  pipeline :authenticated do
    plug(:browser)
    plug(:authentication_required)
  end

  pipeline :admin_rights do
    plug(:authenticated)
    plug(:transport_data_gouv_member)
  end

  pipeline :backoffice_csv_export do
    plug(:check_export_secret_key)
  end

  pipeline :backoffice_clear_proxy_config do
    plug(:check_proxy_config_key)
  end

  pipeline :producer_space do
    plug(:browser)
    plug(:authentication_required, destination_path: "/infos_producteurs")
  end

  pipeline :reuser_space do
    plug(:browser)
    plug(:authentication_required, destination_path: "/infos_reutilisateurs")
  end

  scope "/", OpenApiSpex.Plug do
    pipe_through(:browser_no_csp)

    # NOTE: version of SwaggerUI is currently hardcoded by the Elixir package.
    # See: https://github.com/open-api-spex/open_api_spex/issues/559
    get("/swaggerui", SwaggerUI,
      path: "/api/openapi",
      # See: https://github.com/etalab/transport-site/issues/3421
      syntax_highlight: false
    )
  end

  if Mix.env() == :dev do
    scope "/dev" do
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  scope "/", TransportWeb do
    scope "/backoffice", Backoffice, as: :backoffice do
      pipe_through([:backoffice_clear_proxy_config])

      post("/clear_proxy_config", PageController, :clear_proxy_config)
    end

    scope "/backoffice", Backoffice, as: :backoffice do
      pipe_through([:browser_no_csp, :authentication_required, :transport_data_gouv_member])

      live_session :email_preview, root_layout: {TransportWeb.LayoutView, :app} do
        live("/email_preview", EmailPreviewLive)
      end
    end
  end

  scope "/", TransportWeb do
    pipe_through(:browser)
    get("/", PageController, :index)
    get("/missions", PageController, :missions)
    get("/accessibilite", PageController, :accessibility)
    get("/infos_producteurs", PageController, :infos_producteurs)
    get("/infos_reutilisateurs", PageController, :infos_reutilisateurs)
    get("/robots.txt", PageController, :robots_txt)
    get("/.well-known/security.txt", PageController, :security_txt)
    get("/humans.txt", PageController, :humans_txt)
    get("/sitemap.txt", PageController, :sitemap_txt)
    get("/reuses", ReuseController, :index)

    scope "/espace_producteur" do
      pipe_through([:producer_space])
      get("/", PageController, :espace_producteur)
      get("/proxy_statistics", EspaceProducteurController, :proxy_statistics)
      get("/download_statistics_csv", EspaceProducteurController, :download_statistics_csv)

      scope "/datasets" do
        get("/:dataset_id/edit", EspaceProducteurController, :edit_dataset)
        get("/:dataset_id/reuser_improved_data/:resource_id", EspaceProducteurController, :reuser_improved_data)
        post("/:dataset_id/upload_logo", EspaceProducteurController, :upload_logo)
        delete("/:dataset_id/custom_logo", EspaceProducteurController, :remove_custom_logo)

        scope("/:dataset_id/resources") do
          get("/:resource_datagouv_id/delete", EspaceProducteurController, :delete_resource_confirmation)
          get("/new_resource/", EspaceProducteurController, :new_resource)
          get("/:resource_datagouv_id/", EspaceProducteurController, :edit_resource)
        end

        scope "/:dataset_datagouv_id/resources" do
          post("/", EspaceProducteurController, :post_file)
          delete("/:resource_datagouv_id/delete", EspaceProducteurController, :delete_resource)
          post("/:resource_datagouv_id/", EspaceProducteurController, :post_file)
        end
      end

      live_session :espace_producteur, session: %{"role" => :producer}, root_layout: {TransportWeb.LayoutView, :app} do
        live("/notifications", Live.NotificationsLive, :notifications, as: :espace_producteur)
      end
    end

    scope "/espace_reutilisateur" do
      pipe_through([:reuser_space])
      get("/", ReuserSpaceController, :espace_reutilisateur)
      get("/datasets/:dataset_id", ReuserSpaceController, :datasets_edit)
      post("/datasets/:dataset_id/add_improved_data", ReuserSpaceController, :add_improved_data)
      post("/datasets/:dataset_id/unfavorite", ReuserSpaceController, :unfavorite)
      get("/settings", ReuserSpaceController, :settings)
      get("/settings/new_token", ReuserSpaceController, :new_token)
      post("/settings/new_token", ReuserSpaceController, :create_new_token)
      delete("/settings/tokens/:id", ReuserSpaceController, :delete_token)
      post("/settings/tokens/:id/default_token", ReuserSpaceController, :default_token)

      live_session :reuser_space, session: %{"role" => :reuser}, root_layout: {TransportWeb.LayoutView, :app} do
        live("/notifications", Live.NotificationsLive, :notifications, as: :reuser_space)
      end
    end

    get("/stats", StatsController, :index)
    get("/atom.xml", AtomController, :index)
    post("/send_mail", ContactController, :send_mail)
    get("/aoms", AOMSController, :index)
    get("/aoms.csv", AOMSController, :csv)

    scope "/explore" do
      get("/", ExploreController, :index)
      get("/vehicle-positions", ExploreController, :vehicle_positions)
      get("/gtfs-stops", ExploreController, :gtfs_stops)
    end

    scope "/datasets" do
      get("/", DatasetController, :index)
      get("/:slug/", DatasetController, :details)
      get("/:dataset_id/resources_history_csv", DatasetController, :resources_history_csv)
      get("/region/:region", DatasetController, :by_region)
      get("/departement/:departement", DatasetController, :by_departement_insee)
      get("/epci/:epci", DatasetController, :by_epci)
      get("/commune/:commune", DatasetController, :by_commune_insee)
      get("/offer/:identifiant_offre", DatasetController, :by_offer)

      scope "/:dataset_datagouv_id" do
        pipe_through([:authenticated])
        post("/discussions", DiscussionController, :post_discussion)
        post("/discussions/:discussion_id", DiscussionController, :post_answer)
      end
    end

    scope "/resources" do
      get("/:id", ResourceController, :details)
      get("/:id/download", ResourceController, :download)

      scope "/conversions" do
        get("/:resource_id/:convert_to", ConversionController, :get)
      end
    end

    scope "/backoffice", Backoffice, as: :backoffice do
      pipe_through([:admin_rights])
      get("/", PageController, :index)
      get("/dashboard", DashboardController, :index)

      scope "/contacts" do
        get("/", ContactController, :index)
        get("/new", ContactController, :new)
        get("/csv_export", ContactController, :csv_export)
        post("/create", ContactController, :create)
        get("/:id/edit", ContactController, :edit)
        post("/:id/delete", ContactController, :delete)
      end

      scope "/notification_subscription" do
        post("/", NotificationSubscriptionController, :create)
        delete("/:id", NotificationSubscriptionController, :delete)
        delete("/contact/:contact_id/:dataset_id", NotificationSubscriptionController, :delete_for_contact_and_dataset)
      end

      get("/broken-urls", BrokenUrlsController, :index)
      get("/gtfs-export", GTFSExportController, :export)

      live_dashboard("/phoenix-dashboard",
        metrics: Transport.PhoenixDashboardTelemetry,
        csp_nonce_assign_key: :csp_nonce_value
      )

      live_session :backoffice_proxy_config, root_layout: {TransportWeb.LayoutView, :app} do
        live("/proxy-config", ProxyConfigLive)
      end

      live_session :backoffice_jobs, root_layout: {TransportWeb.LayoutView, :app} do
        live("/jobs", JobsLive)
      end

      live_session :cache, root_layout: {TransportWeb.LayoutView, :app} do
        live("/cache", CacheLive)
      end

      live_session :rate_limiter, root_layout: {TransportWeb.LayoutView, :app} do
        live("/rate_limiter", RateLimiterLive)
      end

      get("/import_aoms", PageController, :import_all_aoms)

      live_session :data_import_batch_report, root_layout: {TransportWeb.LayoutView, :app} do
        live("/batch-report", DataImportBatchReportLive)
      end

      live_session :irve_dashboard, root_layout: {TransportWeb.LayoutView, :app} do
        live("/irve-dashboard", IRVEDashboardLive)
      end

      scope "/datasets" do
        get("/new", PageController, :new)
        get("/:id/edit", PageController, :edit)
        post("/:id", DatasetController, :post)
        post("/", DatasetController, :post)
        post("/:id/_import", DatasetController, :import_from_data_gouv_fr)
        post("/:id/_delete", DatasetController, :delete)
        post("/_all_/_import_validate", DatasetController, :import_validate_all)
        post("/_all_/_force_validate_gtfs_transport", DatasetController, :force_validate_gtfs_transport)
        post("/:id/_import_validate", DatasetController, :import_validate_all)
        post("/:id/_resource_format_override", DatasetController, :resource_format_override)
      end

      get("/breaking_news", BreakingNewsController, :index)
      post("/breaking_news", BreakingNewsController, :update_breaking_news)
    end

    scope "/backoffice", Backoffice, as: :backoffice do
      pipe_through([:backoffice_csv_export])
      get("/download_resources_csv", PageController, :download_resources_csv)
    end

    # Authentication

    scope "/login" do
      get("/", SessionController, :new)
      get("/explanation", PageController, :login)
      get("/callback", SessionController, :create)
    end

    get("/logout", SessionController, :delete)

    scope "/validation" do
      live_session :validation, root_layout: {TransportWeb.LayoutView, :app} do
        live("/", Live.OnDemandValidationSelectLive)
      end

      post("/", ValidationController, :validate)
      post("/convert", ValidationController, :convert)
      get("/:id", ValidationController, :show)
    end

    scope "/tools" do
      get("/gbfs/geojson_convert", GbfsToGeojsonController, :convert)
      get("/gbfs/analyze", GbfsAnalyzerController, :index)

      live_session :gtfs_diff, root_layout: {TransportWeb.LayoutView, :app} do
        live("/gtfs_diff", Live.GTFSDiffSelectLive)
      end

      live_session :siri, root_layout: {TransportWeb.LayoutView, :app} do
        live("/siri-querier", Live.SIRIQuerierLive)
      end
    end

    scope "/gtfs-geojson-conversion" do
      pipe_through([:admin_rights])
      get("/", GeojsonConversionController, :index)
      post("/", GeojsonConversionController, :convert)
    end

    get("/landing-vls", LandingPagesController, :vls)

    # old static pages that have been moved to doc.transport
    get("/faq", Redirect,
      external: "https://doc.transport.data.gouv.fr/le-point-d-acces-national/generalites/le-point-dacces-national"
    )

    get("/guide", Redirect,
      external:
        "https://doc.transport.data.gouv.fr/producteurs/operateurs-de-transport-regulier-de-personnes/publier-des-horaires-theoriques-de-transport-regulier"
    )

    get("/legal", Redirect,
      external:
        "https://doc.transport.data.gouv.fr/presentation-et-mode-demploi-du-pan/mentions-legales-et-conditions-generales-dutilisation"
    )

    get("/conditions", Redirect,
      external:
        "https://doc.transport.data.gouv.fr/presentation-et-mode-demploi-du-pan/conditions-dutilisation-des-donnees/licence-odbl"
    )

    get("/budget", Redirect,
      external: "https://doc.transport.data.gouv.fr/le-point-d-acces-national/generalites/budget"
    )

    # old static pages that have been moved to blog.transport
    get("/blog/2019_04_26_interview_my_bus", Redirect,
      external:
        "https://blog.transport.data.gouv.fr/billets/entretien-avec-fr%C3%A9d%C3%A9ric-pacotte-co-fondateur-et-ceo-de-mybus/"
    )

    get("/blog/2019_10_24_itw-gueret", Redirect,
      external:
        "https://blog.transport.data.gouv.fr/billets/cr%C3%A9ation-dun-fichier-gtfs-interview-avec-le-grand-gu%C3%A9ret/"
    )

    get("/blog/2020_01_16_donnees_perimees.md", Redirect,
      external:
        "https://blog.transport.data.gouv.fr/billets/donn%C3%A9es-p%C3%A9rim%C3%A9es-donn%C3%A9es-inutilis%C3%A9es/"
    )

    # Define a "catch all" route, rendering the 404 page.
    # By default pipelines are not invoked when a route is not found.
    # We need the `browser` pipeline in order to start the session.
    #
    # See https://elixirforum.com/t/phoenix-router-no-pipelines-invoked-for-404/42563
    get("/*path", PageController, :not_found)
  end

  # private

  defp assign_mix_env(conn, _) do
    assign(conn, :mix_env, Mix.env())
  end

  defp assign_current_user(conn, _) do
    # `current_user` is set by TransportWeb.SessionController.user_params_for_session/1
    assign(conn, :current_user, get_session(conn, :current_user))
  end

  defp assign_datagouv_token(conn, _) do
    legacy_key = get_session(conn, :token)
    assign(conn, :datagouv_token, get_session(conn, :datagouv_token) || legacy_key)
  end

  defp maybe_login_again(conn, _) do
    case conn.assigns[:datagouv_token] do
      %OAuth2.AccessToken{expires_at: expires_at} ->
        if DateTime.compare(DateTime.from_unix!(expires_at), DateTime.utc_now()) == :lt do
          conn |> configure_session(drop: true) |> assign(:current_user, nil) |> authentication_required(nil)
        else
          conn
        end

      _ ->
        conn
    end
  end

  @doc """
  Checks if the user is logged-in or not and redirects accordingly.

  If the user is logged-in, do nothing.
  If the user is not logged-in, redirects to the login page which then redirects
  to the previous page.

  Available options:
  - `destination_path`: instead of redirecting to the login page, redirect to this path
  """
  def authentication_required(%Plug.Conn{} = conn, nil), do: authentication_required(conn, [])

  def authentication_required(%Plug.Conn{} = conn, options) do
    login_path = Helpers.page_path(conn, :login, redirect_path: current_path(conn))
    destination_path = Keyword.get(options, :destination_path, login_path)

    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:info, dgettext("alert", "You need to be connected before doing this."))
        |> redirect(to: destination_path)
        |> halt()

      _ ->
        conn
    end
  end

  # Check that a secret key is passed in the URL in the `export_key` query parameter
  defp check_export_secret_key(%Plug.Conn{params: params} = conn, _) do
    export_key_value = Map.get(params, "export_key", "")
    expected_value = Application.fetch_env!(:transport, :export_secret_key)

    if Plug.Crypto.secure_compare(export_key_value, expected_value) do
      conn
    else
      conn
      |> put_flash(:error, dgettext("alert", "You need to be a member of the transport.data.gouv.fr team."))
      |> redirect(to: Helpers.page_path(conn, :login, redirect_path: current_path(conn)))
      |> halt()
    end
  end

  defp check_proxy_config_key(%Plug.Conn{} = conn, _) do
    key_value =
      case Plug.Conn.get_req_header(conn, "x-key") do
        [value] -> value
        _ -> ""
      end

    expected_value = Application.fetch_env!(:transport, :proxy_config_secret_key)

    if Plug.Crypto.secure_compare(key_value, expected_value) do
      conn
    else
      conn |> put_status(401) |> text("Unauthorized") |> halt()
    end
  end

  defp transport_data_gouv_member(%Plug.Conn{} = conn, _) do
    if TransportWeb.Session.admin?(conn) do
      conn
    else
      conn
      |> put_flash(:error, dgettext("alert", "You need to be a member of the transport.data.gouv.fr team."))
      |> redirect(to: Helpers.page_path(conn, :login, redirect_path: current_path(conn)))
      |> halt()
    end
  end

  # see https://github.com/remi/plug_canonical_host#usage
  defp canonical_host(conn, _) do
    host = Application.fetch_env!(:transport, :domain_name)
    opts = PlugCanonicalHost.init(canonical_host: host)
    PlugCanonicalHost.call(conn, opts)
  end
end
