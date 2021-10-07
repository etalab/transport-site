defmodule ValidatorTest do
  @moduledoc false

  alias Validator.Gtfs.MobilityDataValidator

  def validate_gtfs(gtfs_file_path),
    do:
      gtfs_file_path
      |> MobilityDataValidator.new()
      |> MobilityDataValidator.execute()
      |> MobilityDataValidator.parse_outputs()
end
