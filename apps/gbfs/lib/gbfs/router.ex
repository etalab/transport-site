defmodule GBFS.Router do
  use GBFS, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/gbfs", GBFS do
    pipe_through :api

    scope "/velomagg" do
      get "/gbfs.json", VelomaggController, :index
      get "/system_information.json", VelomaggController, :system_information
      get "/station_information.json", VelomaggController, :station_information
      get "/station_status.json", VelomaggController, :station_status
    end

    scope "/toulouse" do
      get "/gbfs.json", ToulouseController, :index
      get "/system_information.json", ToulouseController, :system_information
      get "/station_information.json", ToulouseController, :station_information
      get "/station_status.json", ToulouseController, :station_status
    end
  end
end
