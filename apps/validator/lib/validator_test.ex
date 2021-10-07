defmodule ValidatorTest do
  @moduledoc false

  alias Validator.Gtfs.MobilityDataValidator

  def validate_with_notices, do: execute_validation_and_parse_outputs("gtfs-notices.zip")

  def validate_with_file_not_found,
    do: execute_validation_and_parse_outputs("does_not_exists.zip")

  def validate_without_notices, do: execute_validation_and_parse_outputs("gtfs-1-.zip")

  defp execute_validation_and_parse_outputs(gtfs_filename),
    do:
      gtfs_filename
      |> resolve_gtfs_path()
      |> MobilityDataValidator.new()
      |> MobilityDataValidator.execute()
      |> MobilityDataValidator.parse_outputs()

  defp gtfs_validator_directory, do: "/Users/lionel/Devs/projets/etalab/vendors/mobility_data"

  defp resolve_gtfs_path(gtfs_filename), do: Path.join(gtfs_validator_directory(), gtfs_filename)
end
