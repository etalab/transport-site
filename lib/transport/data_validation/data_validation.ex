defmodule Transport.DataValidation do
  @moduledoc """
  The boundary of the DataValidation context.
  """

  alias Transport.DataValidation.Aggregates.Dataset
  alias Transport.DataValidation.Queries.FindDataset
  alias Transport.DataValidation.Commands.{CreateDataset, ValidateDataset}

  @doc """
  Finds a dataset.
  """
  @spec find_dataset(map) :: {:ok, Dataset.t()} | {:error, any}
  def find_dataset(%{} = attrs) do
    attrs
    |> FindDataset.new()
    |> Dataset.execute()
  end

  @doc """
  Creates a dataset.
  """
  @spec create_dataset(map) :: {:ok, Dataset.t()} | {:error, any}
  def create_dataset(%{} = attrs) do
    attrs
    |> CreateDataset.new()
    |> CreateDataset.validate()
    |> case do
      {:ok, command} -> Dataset.execute(command)
      {:error, error} -> {:error, error}
    end
  end

  @doc """
  Validates a dataset.
  """
  @spec validate_dataset(Dataset.t()) :: {:ok, [Dataset.Validation.t()]} | {:error, any}
  def validate_dataset(%Dataset{} = attrs) do
    attrs
    |> ValidateDataset.new()
    |> ValidateDataset.validate()
    |> case do
      {:ok, command} -> Dataset.execute(command)
      {:error, error} -> {:error, error}
    end
  end
end
