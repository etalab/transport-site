defmodule TransportWeb.ValidationController do
  use TransportWeb, :controller
  alias DB.{Repo, Validation}

  import TransportWeb.ResourceView, only: [issue_type: 1]

  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 180_000

  @geojson_converter_url "https://convertisseur.transport.data.gouv.fr/gtfs2geojson_sync"

  defp endpoint, do: Application.get_env(:transport, :gtfs_validator_url) <> "/validate"

  def index(%Plug.Conn{} = conn, _) do
    render(conn, "index.html")
  end

  def validate(%Plug.Conn{} = conn, %{"upload" => upload_params}) do
    # geojson converter accepts only zip files
    file_path = upload_params["file"].path
    file_path_with_extension = file_path <> ".zip"
    File.rename(file_path, file_path_with_extension)

    geojson_converter_response =
      @client.post(
        @geojson_converter_url,
        {:multipart, [{:file, file_path_with_extension}]},
        [{"content-type", "multipart/form-data;"}],
        recv_timeout: @timeout
      )

    geojson_encoded =
      case geojson_converter_response do
        {:ok, %@res{status_code: 200, body: geojson_encoded}} -> geojson_encoded
        _ -> nil
      end

    with {:ok, gtfs} <- File.read(file_path_with_extension),
         {:ok, %@res{status_code: 200, body: body}} <-
           @client.post(endpoint(), gtfs, [], recv_timeout: @timeout),
         {:ok, %{"validations" => validations, "metadata" => metadata}} <- Jason.decode(body) do
      data_vis = validation_data_vis(geojson_encoded, validations)

      %Validation{
        date: DateTime.utc_now() |> DateTime.to_string(),
        details: validations,
        on_the_fly_validation_metadata: metadata,
        data_vis: data_vis
      }
      |> Repo.insert()
    else
      {:error, %@err{reason: error}} -> {:error, error}
      _ -> {:error, "Unknown error in validate"}
    end
    |> case do
      {:ok, %Validation{id: id}} ->
        redirect(conn, to: validation_path(conn, :show, id))

      _ ->
        conn
        |> put_flash(:error, dgettext("validations", "Unable to validate file"))
        |> redirect(to: validation_path(conn, :index))
    end
  end

  @spec validation_data_vis(any, any) :: nil | map
  def validation_data_vis(nil, _), do: nil

  def validation_data_vis(geojson_encoded, validations) do
    case Jason.decode(geojson_encoded) do
      {:ok, geojson} ->
        data_vis_content(geojson, validations)

      _ ->
        %{}
    end
  end

  def data_vis_content(geojson, validations) do
    validations
    |> Map.new(fn {issue_name, issues_list} ->
      issues_map = get_issues_map(issues_list)

      # create a map with with stop id as keys and geojson features as values
      features_map =
        geojson["features"]
        |> Map.new(fn feature -> {feature["properties"]["id"], feature} end)

      issues_geojson = get_issues_geojson(geojson, issues_map, features_map)

      severity = issues_map |> Map.values() |> Enum.at(0) |> Map.get("severity")
      # severity is used to customize the markers color in leaflet
      {issue_name, %{"severity" => severity, "geojson" => issues_geojson}}
    end)
  end

  def get_issues_map(issues_list) do
    # create a map with stops id as keys and issue description as values
    Map.new(issues_list, fn issue ->
      simplified_issue = simplified_issue(issue)

      {issue["object_id"], simplified_issue}
    end)
  end

  def simplified_issue(issue) do
    # keep only on related stop in related objects
    issue
    |> Map.update("related_objects", [], fn related_objects ->
      related_objects |> Enum.filter(fn o -> o["object_type"] == "Stop" end) |> List.first()
    end)
  end

  def get_issues_geojson(geojson, issues_map, features_map) do
    # create a geojson for each issue type
    Map.update(geojson, "features", [], fn _features ->
      issues_map
      |> Enum.flat_map(fn {id, issue} ->
        features_from_issue(issue, id, features_map)
      end)
    end)
  end

  def features_from_issue(issue, id, features_map) do
    # features contains a list of stops, related_stops and Linestrings
    # Linestrings are used to link a stop and its related stop

    case features_map[id] do
      nil ->
        []

      feature ->
        properties = Map.put(feature["properties"] || %{}, "details", Map.get(issue, "details"))
        stop = Map.put(feature, "properties", properties)

        case issue["related_objects"] do
          %{"id" => id, "name" => _name} ->
            related_stop = features_map[id]

            stops_link = %{
              "type" => "Feature",
              "properties" => %{
                "details" => Map.get(issue, "details")
              },
              "geometry" => %{
                "type" => "LineString",
                "coordinates" => [
                  stop["geometry"]["coordinates"],
                  related_stop["geometry"]["coordinates"]
                ]
              }
            }

            [stop, related_stop, stops_link]

          _ ->
            [stop]
        end
    end
  end

  def show(%Plug.Conn{} = conn, %{} = params) do
    config = make_pagination_config(params)
    validation = Repo.get(Validation, params["id"])

    case validation do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(TransportWeb.ErrorView)
        |> render(:"404")

      validation ->
        current_issues = Validation.get_issues(validation, params)

        issue_type =
          case params["issue_type"] do
            nil -> issue_type(current_issues)
            issue_type -> issue_type
          end

        encoded_data_vis =
          case Jason.encode(validation.data_vis[issue_type]) do
            {:ok, "null"} -> nil
            {:ok, data_vis} -> data_vis
            _ -> nil
          end

        conn
        |> assign(:validation_id, params["id"])
        |> assign(:other_resources, [])
        |> assign(:issues, Scrivener.paginate(current_issues, config))
        |> assign(:validation_summary, Validation.summary(validation))
        |> assign(:severities_count, Validation.count_by_severity(validation))
        |> assign(:metadata, validation.on_the_fly_validation_metadata)
        |> assign(:data_vis, encoded_data_vis)
        |> render("show.html")
    end
  end
end
