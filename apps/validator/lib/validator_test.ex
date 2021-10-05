defmodule ValidatorTest do
  @moduledoc false

  alias Validator.Gtfs.MobilityDataValidator

  def validate_with_notices, do: execute_validation_and_parse_outputs("gtfs-notices.zip", "output_notices")

  def validate_with_file_not_found, do: execute_validation_and_parse_outputs("does_not_exists.zip", "output_file_not_found")

  def validate_without_notices, do: execute_validation_and_parse_outputs("gtfs-1-.zip", "output_succeed_without_notices")

  defp execute_validation_and_parse_outputs(gtfs_filename, output_directory_name) do
    with gtfs_path <- gtfs_path(gtfs_filename),
         output_directory_path <- "#{gtfs_validator_directory()}/#{output_directory_name}",
         validation <- MobilityDataValidator.new(gtfs_path, output_directory_path) do
      validation
      |> MobilityDataValidator.execute()
      |> MobilityDataValidator.parse_outputs()
    end
  end

  defp gtfs_validator_directory, do: "/Users/lionel/Devs/projets/etalab/vendors/mobility_data"

  defp gtfs_path(gtfs_filename), do: gtfs_validator_directory() <> "/" <> gtfs_filename
end
