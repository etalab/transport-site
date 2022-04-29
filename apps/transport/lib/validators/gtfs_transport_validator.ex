defmodule Transport.Validators.GTFSTransport do
  @moduledoc """
  Validate a GTFS with transport-validator (https://github.com/etalab/transport-validator/)
  """

  def validate(%DB.ResourceHistory{id: resource_history_id, payload: %{"permanent_url" => url}}) do
    timestamp = DateTime.utc_now()

    with {:ok, %{"validations" => validations, "metadata" => metadata}} <-
           Shared.Validation.GtfsValidator.validate_from_url(url),
         data_vis <- Transport.DataVisualization.validation_data_vis(validations) do
      val = %DB.MultiValidation{
        validation_timestamp: timestamp,
        validator: validator_name(),
        result: validations,
        metadata: metadata,
        data_vis: data_vis,
        command: command(url),
        resource_history_id: resource_history_id
      }

      DB.Repo.insert(val)
    else
      # _ -> {:error, inspect(e)}
      _ -> {:error, "GTFS Transport Validator, validation failed"}
    end
  end

  def validator_name, do: "GTFS transport-validator"

  def command(url), do: Shared.Validation.GtfsValidator.remote_gtfs_validation_query(url)
end
