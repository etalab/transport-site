defmodule Transport.Jobs.OnDemandValidationJob do
  @moduledoc """
  Job in charge of validating a file that has been stored
  on Cellar and tracked by a `DB.Validation` row.

  It validates the file and stores the result in the database.
  """
  use Oban.Worker, tags: ["validation"], max_attempts: 5, queue: :on_demand_validation
  require Logger
  import Ecto.Changeset
  alias DB.{Repo, Validation}
  alias Shared.Validation.GtfsValidator.Wrapper, as: GtfsValidator
  alias Shared.Validation.JSONSchemaValidator.Wrapper, as: JSONSchemaValidator
  alias Shared.Validation.TableSchemaValidator.Wrapper, as: TableSchemaValidator
  alias Transport.DataVisualization
  alias Transport.Jobs.GTFSRTValidationJob

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id, "state" => "waiting"} = payload}) do
    result =
      try do
        perform_validation(payload)
      rescue
        e -> %{"state" => "error", "error_reason" => inspect(e)}
      end

    %{on_the_fly_validation_metadata: on_the_fly_validation_metadata} = validation = Repo.get!(Validation, id)

    validation
    |> change(
      date: DateTime.utc_now() |> DateTime.to_string(),
      details: Map.get(result, "validation"),
      on_the_fly_validation_metadata:
        Map.merge(on_the_fly_validation_metadata, Map.drop(result, ["validation", "data_vis"])),
      data_vis: Map.get(result, "data_vis")
    )
    |> Repo.update!()

    if Map.has_key?(payload, "filename") do
      Transport.S3.delete_object!(:on_demand_validation, payload["filename"])
    end

    :ok
  end

  defp perform_validation(%{"type" => "gtfs", "permanent_url" => url}) do
    case GtfsValidator.impl().validate_from_url(url) do
      {:error, msg} ->
        %{"state" => "error", "error_reason" => msg}

      {:ok, %{"validations" => validation, "metadata" => metadata}} ->
        Map.merge(
          %{
            "state" => "completed",
            "validation" => validation,
            "data_vis" => DataVisualization.validation_data_vis(validation)
          },
          metadata
        )
    end
  end

  defp perform_validation(%{"type" => "tableschema", "permanent_url" => url, "schema_name" => schema_name}) do
    case TableSchemaValidator.validate(schema_name, url) do
      nil ->
        %{"state" => "error", "error_reason" => "could not perform validation"}

      validation ->
        %{"state" => "completed", "validation" => validation}
    end
  end

  defp perform_validation(%{"type" => "jsonschema", "permanent_url" => url, "schema_name" => schema_name}) do
    case JSONSchemaValidator.validate(JSONSchemaValidator.load_jsonschema_for_schema(schema_name), url) do
      nil ->
        %{"state" => "error", "error_reason" => "could not perform validation"}

      validation ->
        %{"state" => "completed", "validation" => validation}
    end
  end

  defp perform_validation(%{"type" => "gtfs-rt", "gtfs_url" => gtfs_url, "gtfs_rt_url" => gtfs_rt_url, "id" => id}) do
    {gtfs_path, gtfs_rt_path} = {filename(id, "gtfs"), filename(id, "gtfs-rt")}

    result =
      [download_from_url(gtfs_url, gtfs_path), download_from_url(gtfs_rt_url, gtfs_rt_path)] |> process_download()

    remove_files([gtfs_path, gtfs_rt_path, gtfs_rt_result_path(gtfs_rt_path)])
    result
  end

  defp normalize_download(result) do
    case result do
      {:error, reason} -> {:error, %{"state" => "error", "error_reason" => reason}}
      {:ok, path, _} -> {:ok, path}
    end
  end

  defp remove_files(paths) do
    paths |> Enum.each(&File.rm(&1))
    paths |> Enum.each(&File.rmdir(Path.dirname(&1)))
  end

  defp process_download([{:ok, gtfs_path}, {:ok, gtfs_rt_path}]) do
    case GTFSRTValidationJob.run_validator(gtfs_path, gtfs_rt_path) do
      {:ok, _} ->
        case GTFSRTValidationJob.convert_validator_report(gtfs_rt_result_path(gtfs_rt_path)) do
          {:ok, validation} ->
            %{"state" => "completed", "validation" => validation}

          :error ->
            %{"state" => "error", "error_reason" => "Could not run validator. Please provide a GTFS and a GTFS-RT."}
        end

      {:error, reason} ->
        %{"state" => "error", "error_reason" => inspect(reason)}
    end
  end

  defp process_download(results) do
    results |> Enum.find(fn {k, _} -> k == :error end) |> elem(1)
  end

  def filename(validation_id, format) when format in ["gtfs", "gtfs-rt"] do
    folder = System.tmp_dir!() |> Path.join("validation_#{validation_id}_gtfs_rt")
    File.mkdir_p!(folder)
    extension = Map.fetch!(%{"gtfs" => "zip", "gtfs-rt" => "bin"}, format)
    Path.join([folder, "file.#{extension}"])
  end

  def gtfs_rt_result_path(gtfs_rt_path) do
    # https://github.com/CUTR-at-USF/gtfs-realtime-validator/blob/master/gtfs-realtime-validator-lib/README.md#output
    gtfs_rt_path <> ".results.json"
  end

  defp download_from_url(url, path) do
    result =
      case http_client().get(url, [], follow_redirect: true) do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          Logger.debug("Saving #{url} to #{path}")
          File.write!(path, body)
          {:ok, path, body}

        {:ok, %HTTPoison.Response{status_code: status}} ->
          {:error, "Got a non 200 status: #{status}"}

        {:error, %HTTPoison.Error{reason: reason}} ->
          {:error, "Got an error: #{reason}"}
      end

    normalize_download(result)
  end

  defp http_client, do: Transport.Shared.Wrapper.HTTPoison.impl()
end
