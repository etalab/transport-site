defmodule TransportWeb.Router do
  use TransportWeb, :router
  use Sentry.PlugCapture

  defimpl Plug.Exception, for: Phoenix.Template.UndefinedError do
    def status(_exception), do: 404
    def actions(e), do: [%{label: "Not found", handler: {IO, :puts, ["Template not found: #{inspect(e)}"]}}]
  end

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:protect_from_forgery)
    plug(TransportWeb.Plugs.CustomSecureBrowserHeaders)
    plug(:put_locale)
    plug(:assign_current_user)
    plug(:assign_contact_email)
    plug(:assign_token)
    plug(:maybe_login_again)
    plug(:assign_mix_env)
    plug(Sentry.PlugContext)
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

  get("/swaggerui", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi")

  scope "/", TransportWeb do
    pipe_through(:browser)

    get("/", PageController, :index)
    get("/real_time", PageController, :real_time)
    get("/accessibilite", PageController, :accessibility)
    get("/infos_producteurs", PageController, :infos_producteurs)
    get("/.well-known/security.txt", PageController, :security_txt)

    scope "/espace_producteur" do
      pipe_through([:authenticated])
      get("/", PageController, :espace_producteur)
    end

    get("/stats", StatsController, :index)
    get("/atom.xml", AtomController, :index)
    post("/send_mail", ContactController, :send_mail)
    get("/aoms", AOMSController, :index)
    get("/aoms.csv", AOMSController, :csv)

    scope "/explore" do
      get("/", ExploreController, :index)
      get("/vehicle-positions", ExploreController, :vehicle_positions)
    end

    scope "/datasets" do
      get("/", DatasetController, :index)
      get("/:slug/", DatasetController, :details)
      get("/aom/:aom", DatasetController, :by_aom)
      get("/region/:region", DatasetController, :by_region)
      get("/commune/:insee_commune", DatasetController, :by_commune_insee)

      scope "/:dataset_id" do
        pipe_through([:authenticated])
        post("/followers", FollowerController, :toggle)
        post("/discussions", DiscussionController, :post_discussion)
        post("/discussions/:id_", DiscussionController, :post_answer)
      end
    end

    scope "/resources" do
      get("/:id", ResourceController, :details)
      get("/:id/download", ResourceController, :download)

      scope "/update" do
        pipe_through([:authenticated])
        get("/_choose_action", ResourceController, :choose_action)
        get("/datasets", ResourceController, :datasets_list)

        scope "/datasets/:dataset_id/resources" do
          get("/", ResourceController, :resources_list)
          post("/", ResourceController, :post_file)
          get("/_new_resource/", ResourceController, :form)
          get("/:resource_id/", ResourceController, :form)
          post("/:resource_id/", ResourceController, :post_file)
        end
      end
    end

    scope "/backoffice", Backoffice, as: :backoffice do
      pipe_through([:admin_rights])
      get("/", PageController, :index)

      get("/dashboard", DashboardController, :index)
      # NOTE: by default no layout are automatically picked at time of writing
      # for live views, so an explicit call is needed
      # See https://hexdocs.pm/phoenix_live_view/live-layouts.html

      live_session :backoffice_proxy_config,
        root_layout: {TransportWeb.LayoutView, :app},
        session: {TransportWeb.Backoffice.ProxyConfigLive, :build_session, []} do
        live("/proxy-config", ProxyConfigLive)
      end

      live_session :backoffice_jobs,
        root_layout: {TransportWeb.LayoutView, :app},
        session: {TransportWeb.Backoffice.JobsLive, :build_session, []} do
        live("/jobs", JobsLive)
      end

      live_session :gbfs,
        root_layout: {TransportWeb.LayoutView, :app},
        session: {TransportWeb.Backoffice.GBFSLive, :build_session, []} do
        live("/gbfs", GBFSLive)
      end

      get("/import_aoms", PageController, :import_all_aoms)

      scope "/datasets" do
        get("/new", PageController, :new)
        get("/:id/edit", PageController, :edit)
        post("/", DatasetController, :post)
        post("/:id/_import", DatasetController, :import_from_data_gouv_fr)
        post("/:id/_delete", DatasetController, :delete)
        post("/_all_/_import_validate", DatasetController, :import_validate_all)
        post("/_all_/_validate", DatasetController, :validate_all)
        post("/_all_/_force_validate", DatasetController, :force_validate_all)
        post("/:id/_import_validate", DatasetController, :import_validate_all)
        post("/:id/_validate", DatasetController, :validation)
      end

      get("/breaking_news", BreakingNewsController, :index)
      post("/breaking_news", BreakingNewsController, :update_breaking_news)
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
    end

    scope "/gtfs-geojson-conversion-#{System.get_env("TRANSPORT_TOOLS_SECRET_TOKEN")}" do
      get("/", GeojsonConversionController, :index)
      post("/", GeojsonConversionController, :convert)
    end

    # old static pages that have been moved to doc.transport
    get("/faq", Redirect, external: "https://doc.transport.data.gouv.fr/foire-aux-questions-1/generalites")

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

  defp put_locale(conn, _) do
    case conn.params["locale"] || get_session(conn, :locale) do
      nil ->
        Gettext.put_locale("fr")
        conn |> put_session(:locale, "fr")

      locale ->
        Gettext.put_locale(locale)
        conn |> put_session(:locale, locale)
    end
  end

  defp assign_mix_env(conn, _) do
    assign(conn, :mix_env, Mix.env())
  end

  defp assign_current_user(conn, _) do
    assign(conn, :current_user, get_session(conn, :current_user))
  end

  defp assign_contact_email(conn, _) do
    assign(conn, :contact_email, Application.get_env(:transport, :contact_email))
  end

  defp assign_token(conn, _) do
    assign(conn, :token, get_session(conn, :token))
  end

  defp maybe_login_again(conn, _) do
    case conn.assigns[:token] do
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

  defp authentication_required(conn, _) do
    case conn.assigns[:current_user] do
      nil ->
        conn
        |> put_flash(:info, dgettext("alert", "You need to be connected before doing this."))
        |> redirect(to: Helpers.page_path(conn, :login, redirect_path: current_path(conn)))
        |> halt()

      _ ->
        conn
    end
  end

  # NOTE: method visibility set to public because we need to call the same logic from LiveView
  def is_transport_data_gouv_member?(current_user) do
    current_user
    |> Map.get("organizations", [])
    |> Enum.any?(fn org -> org["slug"] == "equipe-transport-data-gouv-fr" end)
  end

  defp transport_data_gouv_member(conn, _) do
    if is_transport_data_gouv_member?(conn.assigns[:current_user]) do
      conn
    else
      conn
      |> put_flash(:error, dgettext("alert", "You need to be a member of the transport.data.gouv.fr team."))
      |> redirect(to: Helpers.page_path(conn, :login, redirect_path: current_path(conn)))
      |> halt()
    end
  end
end
