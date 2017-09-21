defmodule TransportWeb.Router do
  use TransportWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :assign_current_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", TransportWeb do
    pipe_through :browser

    get "/", PageController, :index

    # Authentication

    scope "/login" do
      get "/", SessionController, :new
      get "/explanations", SessionController, :explanations
      get "/oauth/datagouvfr/callback", SessionController, :create
    end

    get "/logout", SessionController, :delete
  end

  defp assign_current_user(conn, _) do
    assign(conn, :current_user, get_session(conn, :current_user))
  end

  # Other scopes may use custom stacks.
  # scope "/api", TransportWeb do
  #   pipe_through :api
  # end
end
