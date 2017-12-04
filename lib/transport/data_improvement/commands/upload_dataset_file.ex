defmodule Transport.DataImprovement.UploadDatasetFile do
  @moduledoc """
  Command for uploading an improved version of a dataset file.

  ## Examples

      iex> %{dataset_id: "5976423a-ee35-11e3-8569-14109ff1a304", file: %Plug.Upload{}}
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

  defstruct [:dataset_id, :file]
  use Transport.DataImprovement.Macros, :command

  @type t :: %__MODULE__{
    dataset_id: String.t,
    file: %Plug.Upload{}
  }

  validates :dataset_id, presence: dgettext("dataset", "Invalid dataset identifier")
  validates :file, by: &__MODULE__.validate_file/1

  @doc """
  Validates the file to upload.

  ## Examples

      iex> UploadDatasetFile.validate_file(%Plug.Upload{})
      :ok

      iex> UploadDatasetFile.validate_file(%{})
      {:error, "A dataset file is needed"}

  """
  @spec validate_file(%Plug.Upload{}) :: :ok | {:error, String.t}
  def validate_file(%Plug.Upload{} = _), do: :ok
  def validate_file(_), do: {:error, dgettext("dataset", "A dataset file is needed")}
end
