defmodule TransportWeb.API.Router do
  use TransportWeb, :router
  use Sentry.PlugCapture

  pipeline :accept_json do
    plug(:accepts, ["json"])
  end

  pipeline :api do
    plug(CORSPlug, origin: "*", credentials: false)
    plug(OpenApiSpex.Plug.PutApiSpec, module: TransportWeb.API.Spec)
    plug(Sentry.PlugContext)
    plug(ETag.Plug)
  end

  pipeline :public_cache do
    plug(TransportWeb.API.Plugs.PublicCache, max_age: 60)
  end

  # Authorization for the GTFS validator.
  # The list of `(user, secret)` is set manually through the app config.
  pipeline :simple_token_auth do
    plug(TransportWeb.API.Plugs.Auth)
  end

  # Authenticate users using the `token` table.
  pipeline :token_auth do
    plug(TransportWeb.API.Plugs.TokenAuth)
  end

  scope "/api/" do
    pipe_through([:accept_json, :api, :token_auth])
    get("/", TransportWeb.Redirect, to: "/swaggerui")

    scope "/aoms" do
      get("/", TransportWeb.API.AomController, :by_coordinates)
      get("/geojson", TransportWeb.API.AomController, :geojson)
      get("/:insee", TransportWeb.API.AomController, :by_insee)
    end

    scope "/stats" do
      get("/", TransportWeb.API.StatsController, :index)
      get("/vehicles-sharing", TransportWeb.API.StatsController, :vehicles_sharing)
      get("/quality", TransportWeb.API.StatsController, :quality)
    end

    get("/openapi", OpenApiSpex.Plug.RenderSpec, :show)

    scope "/autocomplete" do
      pipe_through(:public_cache)

      get("/", TransportWeb.API.AutocompleteController, :autocomplete)
    end

    scope "/datasets" do
      pipe_through(:public_cache)

      get("/", TransportWeb.API.DatasetController, :datasets)
      get("/:id", TransportWeb.API.DatasetController, :by_id)
      get("/:id/geojson", TransportWeb.API.DatasetController, :geojson_by_id)
    end

    scope "/geo-query" do
      get("/", TransportWeb.API.GeoQueryController, :index)
    end

    get("/gtfs-stops", TransportWeb.API.GTFSStopsController, :index)
  end

  scope "/api" do
    pipe_through([:accept_json, :api, :simple_token_auth])

    scope "/validators" do
      get("/gtfs-transport", TransportWeb.API.ValidatorsController, :gtfs_transport)
    end
  end

  @spec swagger_info :: %{info: %{title: binary(), version: binary()}}
  def swagger_info,
    do: %{
      info: %{
        version: "1.0",
        title: "transport.data.gouv.fr API"
      }
    }
end
