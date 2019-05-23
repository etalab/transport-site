defmodule GBFS do
  @moduledoc false

  def controller do
    quote do
      use Phoenix.Controller, namespace: GBFS
      import Plug.Conn
      alias GBFS.Router.Helpers, as: Routes
    end
  end

  def view do
    quote do
      use Phoenix.View,
        root: "lib/gbfs/templates",
        namespace: GBFS

      import Phoenix.Controller, only: [get_flash: 1, get_flash: 2, view_module: 1]

      alias GBFS.Router.Helpers, as: Routes
    end
  end

  def router do
    quote do
      use Phoenix.Router
      import Plug.Conn
      import Phoenix.Controller
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
