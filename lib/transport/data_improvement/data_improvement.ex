defmodule Transport.DataImprovement do
  @moduledoc """
  The boundary of the DataValidation context.
  """

  alias Transport.DataImprovement.Dataset
  alias Transport.DataImprovement.DatasetRepository
  alias Transport.DataImprovement.UploadDatasetFile

  @doc """
  Uploads an improved version of a dataset file and appends it to an existing
  dataset.

  It should have no idea of %Plug.Conn{}, which normally is to be appended to
  the user process state.
  """
  @spec upload_dataset_file(%Plug.Conn{}, map()) :: :ok | {:error, any()}
  def upload_dataset_file(%Plug.Conn{} = conn, %{} = params) do
    params
    |> UploadDatasetFile.new
    |> UploadDatasetFile.validate
    |> case do
      {:ok, command} ->
        command
        |> Dataset.new
        |> DatasetRepository.update_file(conn)
      {:error, errors} ->
        {:validation_error, errors}
    end
  end
end
