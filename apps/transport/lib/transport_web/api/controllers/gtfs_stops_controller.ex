defmodule TransportWeb.API.GTFSStopsController do
  use TransportWeb, :controller

  @max_points 20_000

  @doc """
  This function is used both for the map at /explore/gtfs-stops or as standalone API endpoint
  """
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
