defmodule GBFS.RedirectController do
  use GBFS, :controller

  def index(%Plug.Conn{assigns: %{redirect_params: %{redirects: redirects}}} = conn, %{"path" => path}) do
    if Map.has_key?(redirects, path) do
      base = Map.fetch!(redirects, path)
      destination = base |> URI.merge(path) |> to_string()
      conn |> put_status(301) |> redirect(external: destination)
    else
      conn |> put_status(:not_found) |> text("404 not found")
    end
  end
end
