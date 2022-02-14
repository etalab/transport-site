defmodule Transport.Jobs.OnDemandValidationJob do
  @moduledoc """
  Job in charge of dispatching multiple `MigrateHistoryJob`.

  The goal is to migrate resources that have been historicized
  by the old system to the new system.
  It ignores objects that have already been backed up.
  """
  use Oban.Worker, tags: ["validation"], max_attempts: 5
  require Logger
  import Ecto.Changeset
  alias DB.{Repo, Validation}
  alias Shared.Validation.GtfsValidator.Wrapper, as: GtfsValidator
  alias Shared.Validation.JSONSchemaValidator.Wrapper, as: JSONSchemaValidator
  alias Shared.Validation.TableSchemaValidator.Wrapper, as: TableSchemaValidator
  alias Transport.DataVisualization

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"id" => id, "state" => "waiting", "filename" => filename} = payload}) do
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
        Map.merge(on_the_fly_validation_metadata, map_remove_keys(result, ["validation", "data_vis"])),
      data_vis: Map.get(result, "data_vis")
    )
    |> Repo.update!()

    Transport.S3.delete_object!(:on_demand_validation, filename)

    :ok
  end

  defp map_remove_keys(m, keys) when is_map(m) do
    :maps.filter(fn k, _ -> k not in keys end, m)
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
end
