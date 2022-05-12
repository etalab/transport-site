defmodule Transport.Validators.GTFSTransport do
  @moduledoc """
  Validate a GTFS with transport-validator (https://github.com/etalab/transport-validator/)
  """
  @behaviour Transport.Validators.Validator

  @doc """
  Validates a resource history and extract metadata from it.
  Store the results in DB
  """
  @impl Transport.Validators.Validator
  def validate_and_save(%DB.ResourceHistory{id: resource_history_id, payload: %{"permanent_url" => url}}) do
    timestamp = DateTime.utc_now()
    validator = Shared.Validation.GtfsValidator.Wrapper.impl()

    with {:ok, %{"validations" => validations, "metadata" => metadata}} <-
           validator.validate_from_url(url),
         data_vis <- Transport.DataVisualization.validation_data_vis(validations) do
      metadata = %DB.ResourceMetadata{
        resource_history_id: resource_history_id,
        metadata: metadata
      }

      %DB.MultiValidation{
        validation_timestamp: timestamp,
        validator: validator_name(),
        result: validations,
        data_vis: data_vis,
        command: command(url),
        resource_history_id: resource_history_id,
        metadata: metadata
      }
      |> DB.Repo.insert!()

      :ok
    else
      e -> {:error, "#{validator_name()}, validation failed. #{inspect(e)}"}
    end
  end

  @impl Transport.Validators.Validator
  def validator_name, do: "GTFS transport-validator"

  defp command(url), do: Shared.Validation.GtfsValidator.remote_gtfs_validation_query(url)
end
