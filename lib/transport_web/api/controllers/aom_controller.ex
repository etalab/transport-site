defmodule TransportWeb.API.AomController do
  use TransportWeb, :controller
  alias Transport.{AOM, Repo}
  import Ecto.Query

  def by_coordinates(conn, %{"lon" => lon, "lat" => lat}) do
    with {longitude, _} <- Float.parse(lon),
         {latitude, _} <- Float.parse(lat)
    do
      query(conn, longitude, latitude)
    else
      _ -> invalid_parameters(conn)
    end
  end
  def by_coordinates(conn, _), do: invalid_parameters(conn)

  def query(conn, lon, lat) do
    query = from a in AOM,
              select: map(a, [:nom,
                              :insee_commune_principale,
                              :departement,
                              :forme_juridique,
                              :siren]),
              where: fragment("st_contains(geom, st_point(?, ?))", ^lon, ^lat)

    render(conn, data: Repo.one(query))
  end

  def invalid_parameters(conn) do
    render(conn, data: %{"error" => "The parameters lon and lat are mandatory and must be floats"})
  end

end
