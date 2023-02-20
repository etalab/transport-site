defmodule GBFS.RedirectController do
  use GBFS, :controller

  def index(%Plug.Conn{assigns: %{redirect_params: %{redirects: redirects}}} = conn, %{"path" => path}) do
    case Map.get(redirects, path) do
      nil -> conn |> put_status(:not_found) |> text("404 not found")
      destination -> conn |> put_status(301) |> redirect(external: destination)
    end
  end
end
