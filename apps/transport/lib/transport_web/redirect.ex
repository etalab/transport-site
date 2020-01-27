defmodule TransportWeb.Redirect do
  @moduledoc """
  Redirect utility to be able to add routes like
  get("/example", Redirect, external: "https://example.com")
  """
  import Phoenix.Controller
  import Plug.Conn

  def init([external: _] = opts), do: opts
  def init(_default), do: raise("Missing required external: option in redirect")

  def call(conn, opts) do
    conn
    |> redirect(opts)
    |> halt()
  end
end
