defmodule TransportWeb.ValidationController do
  use TransportWeb, :controller
  alias DB.{Repo, Validation}
  alias Transport.DataVisualisation

  import TransportWeb.ResourceView, only: [issue_type: 1]

  @client HTTPoison
  @res HTTPoison.Response
  @err HTTPoison.Error
  @timeout 180_000

  @geojson_converter_url "https://convertisseur.transport.data.gouv.fr/gtfs2geojson_sync"

  defp endpoint, do: Application.fetch_env!(:transport, :gtfs_validator_url) <> "/validate"

  def index(%Plug.Conn{} = conn, _) do
    render(conn, "index.html")
  end

  def validate(%Plug.Conn{} = conn, %{"upload" => upload_params}) do
    # geojson converter accepts only zip files
    file_path = upload_params["file"].path
    file_path_with_extension = file_path <> ".zip"
    File.rename(file_path, file_path_with_extension)

    geojson_encoded = DataVisualisation.convert_to_geojson(file_path_with_extension)

    with {:ok, gtfs} <- File.read(file_path_with_extension),
         {:ok, %@res{status_code: 200, body: body}} <- @client.post(endpoint(), gtfs, [], recv_timeout: @timeout),
         {:ok, %{"validations" => validations, "metadata" => metadata}} <- Jason.decode(body) do
      data_vis = DataVisualisation.validation_data_vis(geojson_encoded, validations)

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

        data_vis = validation.data_vis[issue_type]
        has_features = not (data_vis["geojson"]["features"] == [])

        encoded_data_vis =
          case {has_features, Jason.encode(data_vis)} do
            {false, _} -> nil
            {true, {:ok, encoded_data_vis}} -> encoded_data_vis
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
