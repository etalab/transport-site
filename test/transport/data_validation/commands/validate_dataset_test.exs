defmodule Transport.DataValidation.Commands.ValidateDatasetTest do
  use ExUnit.Case, async: true
  alias Transport.DataValidation.Aggregates.Dataset
  alias Transport.DataValidation.Commands.ValidateDataset

  doctest ValidateDataset
end
