defmodule TransportWeb.ValidationController do
  use TransportWeb, :controller
  alias DB.{MultiValidation, Repo}
  alias Transport.DataVisualization
  import TransportWeb.ResourceView, only: [issue_type: 1]
  import Ecto.Query

  def validate(%Plug.Conn{} = conn, %{"upload" => %{"url" => url, "type" => "gbfs"} = params}) do
    %MultiValidation{
      oban_args: build_oban_args(params),
      validation_timestamp: DateTime.utc_now(),
      validator: Transport.GBFSMetadata.validator_name(),
      validated_data_name: url
    }
    |> Repo.insert!()

    # for the moment, on demand GBFS validations results are not stored in DB
    redirect(conn, to: gbfs_analyzer_path(conn, :index, url: url))
  end

  def validate(%Plug.Conn{} = conn, %{"upload" => %{"url" => _, "feed_url" => _, "type" => "gtfs-rt"} = params}) do
    validation =
      %MultiValidation{
        validator: temporary_on_demand_validator_name(),
        oban_args: build_oban_args(params),
        validation_timestamp: DateTime.utc_now()
      }
      |> Repo.insert!()

    case dispatch_validation_job(validation) do
      :ok ->
        redirect_to_validation_show(conn, validation)

      :error ->
        conn
        |> put_flash(
          :error,
          dgettext(
            "validations",
            "Each GTFS-RT feed can only be validated once per 5 minutes. Please wait a moment and try again."
          )
        )
        |> redirect(
          to:
            live_path(
              conn,
              TransportWeb.Live.OnDemandValidationSelectLive,
              params |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
            )
        )
    end
  end

  def validate(%Plug.Conn{} = conn, %{
        "upload" => %{"file" => %{path: file_path, filename: filename}, "type" => type}
      }) do
    if is_valid_type?(type) do
      oban_args = build_oban_args(type)
      upload_to_s3(file_path, Map.fetch!(oban_args, "filename"))

      validation =
        %MultiValidation{
          validator: temporary_on_demand_validator_name(),
          validation_timestamp: DateTime.utc_now(),
          oban_args: oban_args,
          validated_data_name: filename
        }
        |> Repo.insert!()

      dispatch_validation_job(validation)
      redirect_to_validation_show(conn, validation)
    else
      conn |> bad_request()
    end
  end

  def validate(conn, _) do
    conn |> bad_request()
  end

  defp redirect_to_validation_show(conn, %MultiValidation{
         oban_args: %{"secret_url_token" => token},
         id: id
       }) do
    redirect(conn, to: validation_path(conn, :show, id, token: token))
  end

  def show(%Plug.Conn{} = conn, %{} = params) do
    token = params["token"]
    validation = MultiValidation |> preload(:metadata) |> Repo.get(params["id"])

    case validation do
      nil ->
        not_found(conn)

      %MultiValidation{oban_args: %{"secret_url_token" => expected_token}}
      when expected_token != token ->
        unauthorized(conn)

      %MultiValidation{oban_args: %{"state" => "completed", "type" => "gtfs"}} = validation ->
        # to be updated when PR 2371 is merged
        current_issues = DB.Validation.get_issues(%{details: validation.result}, params)

        issue_type =
          case params["issue_type"] do
            nil -> issue_type(current_issues)
            issue_type -> issue_type
          end

        conn
        |> assign(:validation_id, params["id"])
        |> assign(:other_resources, [])
        |> assign(:issues, Scrivener.paginate(current_issues, make_pagination_config(params)))
        # to be updated when PR 2371 is merged
        |> assign(:validation_summary, DB.Validation.summary(%{details: validation.result}))
        # to be updated when PR 2371 is merged
        |> assign(:severities_count, DB.Validation.count_by_severity(%{details: validation.result}))
        |> assign(:metadata, validation.metadata.metadata)
        |> assign(:data_vis, data_vis(validation, issue_type))
        |> assign(:token, token)
        |> render("show.html")

      # Handles waiting for validation to complete, errors and
      # validation for schemas
      _ ->
        live_render(conn, TransportWeb.Live.OnDemandValidationLive,
          session: %{
            "validation_id" => params["id"],
            "current_url" => validation_path(conn, :show, params["id"], token: token)
          }
        )
    end
  end

  defp data_vis(%MultiValidation{} = validation, issue_type) do
    data_vis = validation.data_vis[issue_type]
    has_features = DataVisualization.has_features(data_vis["geojson"])

    case {has_features, Jason.encode(data_vis)} do
      {false, _} -> nil
      {true, {:ok, encoded_data_vis}} -> encoded_data_vis
      _ -> nil
    end
  end

  defp filepath(type) do
    cond do
      type == "tableschema" -> Ecto.UUID.generate() <> ".csv"
      type in ["jsonschema", "gtfs"] -> Ecto.UUID.generate()
    end
  end

  defp dispatch_validation_job(%MultiValidation{id: id, oban_args: %{"type" => "gtfs-rt"} = oban_args} = validation) do
    oban_args = Map.merge(%{"id" => id}, oban_args)

    oban_return =
      oban_args
      |> Transport.Jobs.OnDemandValidationJob.new(unique: [period: 300, keys: [:type, :gtfs_rt_url, :gtfs_url]])
      |> Oban.insert()

    case oban_return do
      {:ok, %Oban.Job{conflict?: true}} ->
        validation
        |> Ecto.Changeset.change(
          oban_args:
            Map.merge(oban_args, %{"state" => "error", "error_reason" => "Can run this job only once every 5 minutes"})
        )
        |> Repo.update!()

        :error

      _ ->
        :ok
    end
  end

  defp dispatch_validation_job(%MultiValidation{id: id, oban_args: oban_args}) do
    oban_args |> Map.merge(%{"id" => id}) |> Transport.Jobs.OnDemandValidationJob.new() |> Oban.insert!()
  end

  def select_options do
    schemas =
      transport_schemas()
      |> Enum.map(fn {k, v} -> {Map.fetch!(v, "title"), k} end)
      |> Enum.sort_by(&elem(&1, 0))

    ["GTFS", "GTFS-RT", "GBFS"] |> Enum.map(&{&1, String.downcase(&1)}) |> Kernel.++(schemas)
  end

  def is_valid_type?(type), do: type in (select_options() |> Enum.map(&elem(&1, 1)))

  defp upload_to_s3(file_path, path) do
    Transport.S3.upload_to_s3!(:on_demand_validation, File.read!(file_path), path)
  end

  defp build_oban_args(%{"url" => url, "feed_url" => feed_url, "type" => "gtfs-rt"}) do
    %{
      "type" => "gtfs-rt",
      "state" => "waiting",
      "gtfs_rt_url" => feed_url,
      "gtfs_url" => url,
      "secret_url_token" => Ecto.UUID.generate()
    }
  end

  defp build_oban_args(%{"url" => url, "type" => "gbfs"}) do
    %{"type" => "gbfs", "state" => "submitted", "feed_url" => url}
  end

  defp build_oban_args(type) do
    args =
      case type do
        "gtfs" -> %{"type" => "gtfs"}
        schema_name -> %{"schema_name" => schema_name, "type" => schema_type(schema_name)}
      end

    path = filepath(args["type"])

    Map.merge(
      args,
      %{
        "state" => "waiting",
        "filename" => path,
        "permanent_url" => Transport.S3.permanent_url(:on_demand_validation, path),
        "secret_url_token" => Ecto.UUID.generate()
      }
    )
  end

  defp schema_type(schema_name), do: transport_schemas()[schema_name]["schema_type"]

  defp transport_schemas, do: Transport.Shared.Schemas.Wrapper.transport_schemas()

  defp not_found(%Plug.Conn{} = conn) do
    conn
    |> put_status(:not_found)
    |> put_view(TransportWeb.ErrorView)
    |> assign(
      :status_message,
      dgettext(
        "validation",
        "Validation not found. On-demand validation results have been reinitialized on 2022-05-30. Please validate your file again."
      )
    )
    |> render(:"404")
  end

  defp unauthorized(%Plug.Conn{} = conn) do
    conn
    |> put_status(:unauthorized)
    |> put_view(TransportWeb.ErrorView)
    |> render(:"401")
  end

  defp bad_request(%Plug.Conn{} = conn) do
    conn
    |> put_status(:bad_request)
    |> put_view(ErrorView)
    |> render("400.html")
  end

  def temporary_on_demand_validator_name, do: "on demand validation requested"
end
