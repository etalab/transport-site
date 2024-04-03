defmodule TransportWeb.ReuserSpaceController do
  use TransportWeb, :controller

  def espace_reutilisateur(%Plug.Conn{} = conn, _) do
    text(conn, "Coming soon")
  end
end
