defmodule TransportWeb.API.AomController do
  use TransportWeb, :controller
  alias Plug.Conn
  alias Transport.{AOM, Commune, Repo}
  import Ecto.Query
  alias Geo.JSON
  alias OpenApiSpex.Operation
  alias TransportWeb.API.Schemas.{AOMResponse, GeoJSONResponse}

  @aom_fields [:nom, :insee_commune_principale, :departement, :forme_juridique, :siren]

  @spec open_api_operation(any) :: Operation.t
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  def by_coordinates_operation do
    %Operation{
      tags: ["aom"],
      summary: "Show AOM by coordinates",
      description: "Show covered regions",
      operationId: "API.AOMController.by_coordinates",
      parameters: [
        Operation.parameter(:lon, :query, :number, "Longitude"),
        Operation.parameter(:lat, :query, :number, "Latitude")
      ],
      responses: %{
        200 => Operation.response("AOM", "application/json", AOMResponse)
      }
    }
  end

  def by_coordinates(conn, %{"lon" => lon, "lat" => lat}) do
    with {longitude, _} <- Float.parse(lon),
         {latitude, _} <- Float.parse(lat)
    do
      query_by_coordinates(conn, longitude, latitude)
    else
      _ -> invalid_parameters(conn)
    end
  end
  def by_coordinates(conn, _), do: invalid_parameters(conn)

  def by_insee_operation do
    %Operation{
      tags: ["insee"],
      summary: "Show AOM by INSEE",
      description: "Show covered regions",
      operationId: "API.AOMController.by_coordinates",
      parameters: [
        Operation.parameter(:insee, :query, :string, "INSEE")
      ],
      responses: %{
        200 => Operation.response("AOM", "application/json", AOMResponse)
      }
    }
  end

  def by_insee(conn, %{"insee" => insee}) do
    query = from c in Commune,
              left_join: a in assoc(c, :aom_res),
              select: [map(a, @aom_fields), c],
              where: c.insee == ^insee

    data = query
    |> Repo.one
    |> case do
       nil -> %{"error" => "Commune not found"}
      [nil, _] -> %{"error" => "No corresponding AOM found"}
      [aom, _] -> aom
    end

    conn = if Map.has_key?(data, "error") do
      Conn.put_status(conn, :not_found)
    else
      conn
    end

    render(conn, data: data)
  end

  def query_by_coordinates(conn, lon, lat) do
    query = from a in AOM,
              select: map(a, @aom_fields),
              where: fragment("st_contains(geom, st_setsrid(st_point(?, ?), 4326))", ^lon, ^lat)

    render(conn, data: Repo.one(query))
  end

  def invalid_parameters(conn) do
    render(conn, data: %{"error" => "The parameters lon and lat are mandatory and must be floats"})
  end

  def geojson_operation do
    %Operation{
      tags: ["geojson"],
      summary: "Show geojson of AOM",
      description: "Show covered regions",
      operationId: "API.AOMController.by_coordinates",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", GeoJSONResponse)
      }
    }
  end

  def geojson(conn, _params) do
    query = from a in AOM, select: [map(a, @aom_fields), a.geom]

    json = query
    |> Repo.all
    |> Enum.reject(fn [_, geom] -> is_nil(geom) end)
    |> Enum.map(fn [properties, geom] -> %{
        "type" => "Feature",
        "properties" => properties,
        "geometry" => geom |> JSON.encode!
      }end)
    |> Enum.to_list

    render(conn, features: json)
  end
end
