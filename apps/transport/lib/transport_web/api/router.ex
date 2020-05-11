defmodule TransportWeb.API.Router do
  use TransportWeb, :router
  use Plug.ErrorHandler

  pipeline :accept_json do
    plug(:accepts, ["json"])
  end

  pipeline :api do
    plug(CORSPlug, origin: "*")
    plug(OpenApiSpex.Plug.PutApiSpec, module: TransportWeb.API.Spec)
  end

  scope "/api/" do
    pipe_through([:accept_json, :api])

    scope "/aoms" do
      get("/", TransportWeb.API.AomController, :by_coordinates)
      get("/geojson", TransportWeb.API.AomController, :geojson)
      get("/:insee", TransportWeb.API.AomController, :by_insee)
    end

    scope "/stats" do
      get("/", TransportWeb.API.StatsController, :index)
      get("/regions", TransportWeb.API.StatsController, :regions)
      get("/bike-sharing", TransportWeb.API.StatsController, :bike_sharing)
      get("/quality", TransportWeb.API.StatsController, :quality)
    end

    get("/openapi", OpenApiSpex.Plug.RenderSpec, :show)

    get("/places", TransportWeb.API.PlacesController, :autocomplete)

    scope "/datasets" do
      get("/", TransportWeb.API.DatasetController, :datasets)
      get("/:id", TransportWeb.API.DatasetController, :by_id)
      get("/:id/geojson", TransportWeb.API.DatasetController, :geojson_by_id)
    end
  end

  @spec swagger_info :: %{info: %{title: binary(), version: binary()}}
  def swagger_info,
    do: %{
      info: %{
        version: "1.0",
        title: "Transport.data.gouv.fr API"
      }
    }
end
