defmodule TransportWeb.ValidationController do
  use TransportWeb, :controller
  alias DB.{Repo, Validation}

  import TransportWeb.ResourceView, only: [issue_type: 1]

  def index(%Plug.Conn{} = conn, _) do
    conn
    |> assign(:select_options, select_options())
    |> render("index.html")
  end

  def validate(%Plug.Conn{} = conn, %{"upload" => %{"file" => %{path: file_path}, "type" => type}}) do
    if is_valid_type?(type) do
      path = upload_to_s3(file_path, Ecto.UUID.generate())
      metadata = build_metadata(type, path)

      validation = %Validation{on_the_fly_validation_metadata: metadata} |> Repo.insert!()
      dispatch_validation_job(validation)
      redirect(conn, to: "/validation/#{validation.id}")
    else
      conn |> bad_request()
    end
  end

  defp dispatch_validation_job(%Validation{id: id, on_the_fly_validation_metadata: metadata}) do
    oban_args = Map.merge(%{"id" => id}, metadata)
    oban_args |> Transport.Jobs.OnDemandValidationJob.new() |> Oban.insert!()
  end

  defp select_options do
    schemas =
      transport_schemas()
      |> Enum.map(fn {k, v} -> {Map.fetch!(v, "title"), k} end)
      |> Enum.sort_by(&elem(&1, 0))

    [{"GTFS", "gtfs"} | schemas]
  end

  defp is_valid_type?(type), do: type in (select_options() |> Enum.map(&elem(&1, 1)))

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:on_demand_validation, File.read!(file_path), path)
    path
  end

  defp build_metadata(type, path) do
    base = %{
      "state" => "waiting",
      "type" => type,
      "filename" => path,
      "permanent_url" => Transport.S3.permanent_url(:on_demand_validation, path)
    }

    case type do
      "gtfs" -> base
      schema_name -> Map.merge(base, %{"schema_name" => schema_name, "type" => schema_type(schema_name)})
    end
  end

  def validate(conn, _) do
    conn |> bad_request()
  end

  def show(%Plug.Conn{} = conn, %{} = params) do
    config = make_pagination_config(params)
    validation = Repo.get(Validation, params["id"])

    text(conn, "ok")

    # case validation do
    #   nil ->
    #     conn
    #     |> put_status(:not_found)
    #     |> put_view(TransportWeb.ErrorView)
    #     |> render(:"404")

    #   validation ->
    #     current_issues = Validation.get_issues(validation, params)

    #     issue_type =
    #       case params["issue_type"] do
    #         nil -> issue_type(current_issues)
    #         issue_type -> issue_type
    #       end

    #     data_vis = validation.data_vis[issue_type]
    #     has_features = DataVisualization.has_features(data_vis["geojson"])

    #     encoded_data_vis =
    #       case {has_features, Jason.encode(data_vis)} do
    #         {false, _} -> nil
    #         {true, {:ok, encoded_data_vis}} -> encoded_data_vis
    #         _ -> nil
    #       end

    #     conn
    #     |> assign(:validation_id, params["id"])
    #     |> assign(:other_resources, [])
    #     |> assign(:issues, Scrivener.paginate(current_issues, config))
    #     |> assign(:validation_summary, Validation.summary(validation))
    #     |> assign(:severities_count, Validation.count_by_severity(validation))
    #     |> assign(:metadata, validation.on_the_fly_validation_metadata)
    #     |> assign(:data_vis, encoded_data_vis)
    #     |> render("show.html")
    # end
  end

  defp schema_type(schema_name), do: transport_schemas()[schema_name]["type"]

  defp transport_schemas, do: Transport.Shared.Schemas.Wrapper.transport_schemas()

  defp bad_request(conn) do
    conn
    |> put_status(:bad_request)
    |> put_view(ErrorView)
    |> render("400.html")
  end
end
