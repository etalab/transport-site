defmodule TransportWeb.API.GTFSStopsController do
  use TransportWeb, :controller
  alias OpenApiSpex.Operation

  @max_points 20_000
  # NOTE: summary cannot include formatting apparently.
  # DRYing this here for now, until more are published.
  @experimental_summary "(experimental)"
  @experimental_description "**This API point is experimental with no guarantee of stability or continuity, use at your own risk.**"

  @spec open_api_operation(any) :: Operation.t()
  def open_api_operation(action), do: apply(__MODULE__, :"#{action}_operation", [])

  @moduledoc """
  This module is used both as a standalone API endpoint or for the map at /explore/gtfs-stops.
  There is a single index entry function, that accepts either :
  - API use: only the bounding box coordinates
  - Map use: bounding box coordinates + map parameters (width, height, zoom level).

  The behaviour is slightly different depending on the use case.
  - API use:
   - if the bounding box contains too many points, the API returns an error.
   - otherwise, it returns the detailed data as a GeoJSON FeatureCollection.
  - Map use:
   - if the bounding box contains too many points or the zoom level is not high enough, the API returns the clustered data.
   - otherwise, it returns the detailed data as a GeoJSON FeatureCollection.

   The OpenAPI documentation only refers to the API use case, the map use case is not documented.
  """

  @spec index_operation :: OpenApiSpex.Operation.t()
  def index_operation,
    do: %Operation{
      tags: ["gtfs"],
      summary:
        "#{@experimental_summary} Lists stops from all GTFS files of transport.data.gouv.fr found inside a bounding box.",
      description: ~s"#{@experimental_description}
                      This call returns the GTFS stops from all the datasets of transport.data.gouv.fr
                      found inside the provided bounding box, up to #{@max_points} points (above that threshold, an error will be returned). The dataset ID is present in the answer amongst other data.
                      This endpoint is used to power the map at https://transport.data.gouv.fr/explore/gtfs-stops.",
      operationId: "API.GTFSStopsController.index",
      parameters: [
        Operation.parameter(:south, :query, :number, "South (latitude)"),
        Operation.parameter(:north, :query, :number, "North (latitude)"),
        Operation.parameter(:west, :query, :number, "West (longitude)"),
        Operation.parameter(:east, :query, :number, "East (longitude)")
      ],
      responses: %{
        200 => Operation.response("GeoJSON", "application/json", TransportWeb.API.Schemas.GeoJSONResponse),
        422 => Operation.response("ErrorJSON", "application/json", TransportWeb.API.Schemas.ErrorJSONResponse)
      }
    }

  def index(
        conn,
        params
      ) do
    parsed_params = parse_params(params)

    cond do
      parsed_params[:incorrect_params] ->
        conn
        |> put_status(422)
        |> json(%{error: "incorrect parameters"})

      parsed_params[:count] < @max_points &&
          (parsed_params[:zoom_level] >= 10 || parsed_params[:only_coordinate_params]) ->
        # If we’re on the map with a zoom high enough, or if we’re on the API endpoint with a small count
        # we return the GTFS detailed data
        conn
        |> json(
          Transport.GTFSData.build_detailed(
            {parsed_params[:north], parsed_params[:south], parsed_params[:east], parsed_params[:west]}
          )
        )

      parsed_params[:map_params] ->
        # Else, for the map, we return the clustered data
        data =
          Transport.GTFSData.build_clusters_json_encoded(
            {parsed_params[:north], parsed_params[:south], parsed_params[:east], parsed_params[:west]},
            {parsed_params[:snap_x], parsed_params[:snap_y]}
          )

        # We mark the output with a "type" key to make sure the data is interpreted correctly
        # on the client side.
        conn
        |> put_resp_content_type("application/json")
        |> json(%{type: "clustered", data: Jason.Fragment.new(data)})

      parsed_params[:only_coordinate_params] ->
        # In API mode, the bounding box may be too large
        conn
        |> put_status(422)
        |> json(%{error: "bounding box too large: too many points"})
    end
  end

  defp parse_coordinate_params(%{"south" => south, "east" => east, "west" => west, "north" => north}) do
    with {south, ""} <- Float.parse(south),
         {east, ""} <- Float.parse(east),
         {west, ""} <- Float.parse(west),
         {north, ""} <- Float.parse(north) do
      {:ok, {south, east, west, north}}
    else
      :error ->
        :incorrect_params
    end
  end

  defp parse_coordinate_params(_params), do: :no_coordinate_params

  defp parse_map_params(%{"width_pixels" => width, "height_pixels" => height, "zoom_level" => zoom_level}) do
    with {width_px, ""} <- Float.parse(width),
         {height_px, ""} <- Float.parse(height),
         {zoom_level, ""} <- Integer.parse(zoom_level) do
      {:ok, {width_px, height_px, zoom_level}}
    else
      :error ->
        :incorrect_params
    end
  end

  defp parse_map_params(_params), do: :no_map_params

  defp parse_params(params) do
    case parse_coordinate_params(params) do
      {:ok, {south, east, west, north}} ->
        count = Transport.GTFSData.count_points({north, south, east, west})
        result = %{south: south, east: east, west: west, north: north, count: count}

        case parse_map_params(params) do
          {:ok, {width_px, height_px, zoom_level}} ->
            snap_x = abs((west - east) / (width_px / 5.0))
            snap_y = abs((north - south) / (height_px / 5.0))
            Map.merge(result, %{map_params: true, snap_x: snap_x, snap_y: snap_y, zoom_level: zoom_level})

          :no_map_params ->
            Map.put(result, :only_coordinate_params, true)

          :incorrect_params ->
            %{incorrect_params: true}
        end

      _ ->
        %{incorrect_params: true}
    end
  end
end
