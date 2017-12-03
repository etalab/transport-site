defmodule Transport.DataImprovement.UploadDatasetFile do
  @moduledoc """
  Command for uploading an improved version of a dataset file.

  ## Examples

      iex> %{dataset_uuid: "5976423a-ee35-11e3-8569-14109ff1a304", file: %Plug.Upload{}}
      ...> |> UploadDatasetFile.new
      ...> |> UploadDatasetFile.validate
      ...> |> elem(0)
      :ok

      iex> %{}
      ...> |> UploadDatasetFile.new
      ...> |> UploadDatasetFile.validate
      ...> |> elem(0)
      :error

  """

  defstruct [:dataset_uuid, :file]
  use Transport.DataImprovement.Macros, :command

  @type t :: %__MODULE__{
    dataset_uuid: String.t,
    file: %Plug.Upload{}
  }

  validates :dataset_uuid, by: &__MODULE__.validate_uuid/1
  validates :file, by: &__MODULE__.validate_file/1

  @doc """
  Validates the dataset's uuid.

  ## Examples

      iex> UploadDatasetFile.validate_uuid("5976423a-ee35-11e3-8569-14109ff1a304")
      :ok

      iex> UploadDatasetFile.validate_uuid([])
      {:error, "Invalid dataset identifier"}

  """
  @spec validate_uuid(any()) :: :ok | {:error, String.t}
  def validate_uuid(uuid) do
    case UUID.info(uuid) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, dgettext("dataset", "Invalid dataset identifier")}
    end
  end

  @doc """
  Validates the file to upload.

  ## Examples

      iex> UploadDatasetFile.validate_file(%Plug.Upload{})
      :ok

      iex> UploadDatasetFile.validate_file(%{})
      {:error, "A dataset file is needed"}

  """
  @spec validate_uuid(any()) :: :ok | {:error, String.t}
  def validate_file(%Plug.Upload{} = _), do: :ok
  def validate_file(_), do: {:error, dgettext("dataset", "A dataset file is needed")}
end
