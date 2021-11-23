defmodule TransportWeb.ValidationController do
  use TransportWeb, :controller
  alias DB.{Repo, Validation}
  alias Shared.Validation.GtfsValidator
  alias Transport.DataVisualization

  import TransportWeb.ResourceView, only: [issue_type: 1]

  defp endpoint, do: Application.fetch_env!(:transport, :gtfs_validator_url) <> "/validate"

  def index(%Plug.Conn{} = conn, _) do
    render(conn, "index.html")
  end

  def validate(%Plug.Conn{} = conn, %{"upload" => %{"file" => %{path: file_path}}}) do
    with {:ok, gtfs} <- File.read(file_path),
         {:ok, %{"validations" => validations, "metadata" => metadata}} <- GtfsValidator.validate(gtfs) do
      data_vis = DataVisualization.validation_data_vis(validations)

      %Validation{
        date: DateTime.utc_now() |> DateTime.to_string(),
        details: validations,
        on_the_fly_validation_metadata: metadata,
        data_vis: data_vis
      }
      |> Repo.insert()
    else
      {:error, %{reason: error}} -> {:error, error}
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

  def validate(conn, _) do
    conn
    |> put_status(:bad_request)
    |> put_view(ErrorView)
    |> render("400.html")
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
        has_features = DataVisualization.has_features(data_vis["geojson"])

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
