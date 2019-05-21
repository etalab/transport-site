defmodule TransportWeb.API.Router do
  use TransportWeb, :router
  use Plug.ErrorHandler

  pipeline :accept_json do
    plug :accepts, ["json"]
  end

  pipeline :api do
    plug OpenApiSpex.Plug.PutApiSpec, module: TransportWeb.API.Spec
  end

  scope "/" do
    pipe_through [:accept_json, :api]

    scope "/aoms" do
      get "/", TransportWeb.API.AomController, :by_coordinates
      get "/geojson", TransportWeb.API.AomController, :geojson
      get "/:insee", TransportWeb.API.AomController, :by_insee
    end

    scope "/stats" do
      get "/", TransportWeb.API.StatsController, :index
      get "/regions", TransportWeb.API.StatsController, :regions
    end

    get "/openapi", OpenApiSpex.Plug.RenderSpec, :show

    get "/datasets", TransportWeb.API.DatasetController, :datasets
  end

  def swagger_info do
    %{
      info: %{
        version: "1.0",
        title: "Transport.data.gouv.fr API"
      }
    }
  end
end
