defmodule TransportWeb do
  @moduledoc """
  The entrypoint for defining your web interface, such
  as controllers, views, channels and so on.

  This can be used in your application as:

      use TransportWeb, :controller
      use TransportWeb, :view

  The definitions below will be executed for every view,
  controller, etc, so keep them short and clean, focused
  on imports, uses and aliases.

  Do NOT define functions inside the quoted expressions
  below. Instead, define any helper function in modules
  and import those modules here.
  """
  def static_paths,
    do: ~w(js css fonts images data favicon.ico documents BingSiteAuth.xml google5be4b09db1274976.html demo_rt.html)

  def controller do
    quote do
      use Phoenix.Controller, namespace: TransportWeb
      import Plug.Conn
      import TransportWeb.Router.Helpers
      import TransportWeb.Gettext
      import TransportWeb.PaginationHelpers
      alias TransportWeb.ErrorView
      import Phoenix.LiveView.Controller

      unquote(verified_routes())
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/transport_web/templates",
        namespace: TransportWeb

      # Import convenience functions from controllers
      import Phoenix.Controller, only: [get_flash: 2, view_module: 1, get_csrf_token: 0, view_template: 1]

      # Use all HTML functionality (forms, tags, etc)
      use TransportWeb.InputHelpers

      import TransportWeb.Router.Helpers
      import TransportWeb.ErrorHelpers
      import TransportWeb.InputHelpers
      import TransportWeb.Gettext
      import TransportWeb.SeoMetadata
      import Helpers

      import Phoenix.Component, only: [live_render: 3]

      import Plug.Conn, only: [get_session: 2]
    end
  end

  def view_helpers do
    quote do
      unquote(verified_routes())
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
      import TransportWeb.Gettext, only: [dgettext: 2, dngettext: 4]
      alias TransportWeb.Router.Helpers
      import Phoenix.LiveView.Router
    end
  end

  def channel do
    quote do
      use Phoenix.Channel
      import TransportWeb.Gettext
    end
  end

  def serializer do
    quote do
      use JaSerializer
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: TransportWeb.Endpoint,
        router: TransportWeb.Router,
        statics: TransportWeb.static_paths()
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/view/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
