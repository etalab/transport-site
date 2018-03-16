defmodule Transport.ReusableData.Dataset do
  @moduledoc """
  Represents a dataset as it is published by a producer and consumed by a
  reuser.
  """

  defstruct [
    :_id,
    :title,
    :description,
    :logo,
    :spatial,
    :coordinates,
    :licence,
    :slug,
    :download_uri,
    :anomalies,
    :format,
    :celery_task_id,
    :error_count,
    :notice_count,
    :warning_count,
    :valid?,
    :catalogue_id,
    validations: %{},
  ]

  use ExConstructor

  @type t :: %__MODULE__{
    _id:            %BSON.ObjectId{},
    title:          String.t,
    description:    String.t,
    logo:           String.t,
    spatial:        String.t,
    coordinates:    [float()],
    licence:        String.t,
    slug:           String.t,
    download_uri:   String.t,
    anomalies:      [String.t],
    format:         String.t,
    celery_task_id: String.t,
    validations:    Map.t,
    error_count:    integer(),
    notice_count:   integer(),
    warning_count:  integer(),
    valid?:         boolean(),
    catalogue_id:   String.t
  }

  @doc """
  Calculate and add the number of errors to the dataset.
  """
  @spec assign(%__MODULE__{}, :error_count) :: %__MODULE__{}
  def assign(%__MODULE__{} = dataset, :error_count) do
    error_count =
      dataset
      |> Map.get(:validations)
      |> Map.get("errors", [])
      |> Enum.count()

    new(%{dataset | error_count: error_count})
  end

  @doc """
  Calculate and add the number of notices to the dataset.
  """
  @spec assign(%__MODULE__{}, :notice_count) :: %__MODULE__{}
  def assign(%__MODULE__{} = dataset, :notice_count) do
    notice_count =
      dataset
      |> Map.get(:validations)
      |> Map.get("notices", [])
      |> Enum.count()

    new(%{dataset | notice_count: notice_count})
  end

  @doc """
  Calculate and add the number of warnings to the dataset.
  """
  @spec assign(%__MODULE__{}, :warning_count) :: %__MODULE__{}
  def assign(%__MODULE__{} = dataset, :warning_count) do
    warning_count =
      dataset
      |> Map.get(:validations)
      |> Map.get("warnings", [])
      |> Enum.count()

    new(%{dataset | warning_count: warning_count})
  end

  @doc """
  Add whether the dataset is valid or no.
  """
  @spec assign(%__MODULE__{}, :valid?) :: %__MODULE__{}
  def assign(%__MODULE__{} = dataset, :valid?) do
    new(%{dataset | valid?: dataset.error_count == 0})
  end
end
