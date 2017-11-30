defmodule Transport.ReusableData.Dataset do
  @moduledoc """
  Represents a dataset as it is published by a producer and consumed by a
  reuser.
  """
  alias Transport.DataValidator.CeleryTask

  defstruct [
    :_id,
    :title,
    :description,
    :logo,
    :spatial,
    :coordinates,
    :license,
    :slug,
    :download_uri,
    :anomalies,
    :format,
    :celery_task_id,
    :celery_task
  ]

  @type t :: %__MODULE__{
    _id:            %BSON.ObjectId{},
    title:          String.t,
    description:    String.t,
    logo:           String.t,
    spatial:        String.t,
    coordinates:    [float],
    license:        String.t,
    slug:           String.t,
    download_uri:   String.t,
    anomalies:      [String.t],
    format:         String.t,
    celery_task_id: String.t,
    celery_task:    CeleryTask,
  }

  @doc """
  Initialises a licence struct from a given map. Map's keys must be atoms.

  ## Examples

      iex> Dataset.new(%{title: "Dataset"})
      %Dataset{title: "Dataset"}

      iex> Dataset.new(%{"title" => "Dataset"})
      %Dataset{title: nil}

  """
  @spec new(map()) :: %__MODULE__{}
  def new(%{} = attrs) do
    struct(%__MODULE__{}, attrs)
  end
end
