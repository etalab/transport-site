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
        Map.merge(on_the_fly_validation_metadata, Map.drop(result, ["validation", "data_vis"])),
      data_vis: Map.get(result, "data_vis")
    )
    |> Repo.update!()

    Transport.S3.delete_object!(:on_demand_validation, filename)

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
end
