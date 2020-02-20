defmodule TransportWeb.API.AomController do
  use TransportWeb, :controller
  alias Plug.Conn
  alias DB.{AOM, Commune, Repo}
  import Ecto.Query
  alias Geo.JSON
  alias OpenApiSpex.Operation
  alias TransportWeb.API.Schemas.{AOMResponse, GeoJSONResponse}

  @aom_fields [:nom, :insee_commune_principale, :departement, :forme_juridique, :siren]

  @spec open_api_operation(binary()) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @spec by_coordinates_operation :: OpenApiSpex.Operation.t()
  def by_coordinates_operation,
    do: %Operation{
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

  @spec by_coordinates(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_coordinates(conn, %{"lon" => lon, "lat" => lat}) do
    with {longitude, _} <- Float.parse(lon),
         {latitude, _} <- Float.parse(lat) do
      query_by_coordinates(conn, longitude, latitude)
    else
      _ -> invalid_parameters(conn)
    end
  end

  def by_coordinates(conn, _), do: invalid_parameters(conn)

  @spec by_insee_operation :: OpenApiSpex.Operation.t()
  def by_insee_operation,
    do: %Operation{
      tags: ["insee"],
      summary: "Show AOM by INSEE",
      description: "Show covered regions",
      operationId: "API.AOMController.by_insee_operation",
      parameters: [
        Operation.parameter(:insee, :path, :string, "INSEE")
      ],
      responses: %{
        200 => Operation.response("AOM", "application/json", AOMResponse)
      }
    }

  @spec by_insee(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def by_insee(conn, %{"insee" => insee}) do
    data =
      Commune
      |> join(:left, [c], a in assoc(c, :aom_res))
      |> select([c, a], [map(a, @aom_fields), c])
      |> where([c, a], c.insee == ^insee)
      |> Repo.one()
      |> case do
        nil -> %{"error" => "Commune not found"}
        [nil, _] -> %{"error" => "No corresponding AOM found"}
        [aom, _] -> aom
      end

    conn = if Map.has_key?(data, "error"), do: Conn.put_status(conn, :not_found), else: conn

    render(conn, data: data)
  end

  @spec query_by_coordinates(Plug.Conn.t(), number(), number()) :: Plug.Conn.t()
  def query_by_coordinates(conn, lon, lat) do
    aom =
      AOM
      |> select([a], map(a, @aom_fields))
      |> where([a], fragment("st_contains(geom, st_setsrid(st_point(?, ?), 4326))", ^lon, ^lat))
      |> Repo.one()

    render(conn, data: aom)
  end

  @spec invalid_parameters(Plug.Conn.t()) :: Plug.Conn.t()
  def invalid_parameters(conn),
    do: render(conn, data: %{"error" => "The parameters lon and lat are mandatory and must be floats"})

  @spec geojson_operation :: OpenApiSpex.Operation.t()
  def geojson_operation,
    do: %Operation{
      tags: ["geojson"],
      summary: "Show geojson of AOM",
      description: "Show covered regions",
      operationId: "API.AOMController.geojson_operation",
      parameters: [],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", GeoJSONResponse)
      }
    }

  @spec geojson(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def geojson(conn, _params) do
    json =
      AOM
      |> select([a], [map(a, @aom_fields), a.geom])
      |> Repo.all()
      |> Enum.reject(fn [_, geom] -> is_nil(geom) end)
      |> Enum.map(fn [properties, geom] ->
        %{
          "type" => "Feature",
          "properties" => properties,
          "geometry" => JSON.encode!(geom)
        }
      end)

    render(conn, features: json)
  end
end
