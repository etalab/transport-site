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
    :license,
    :slug,
    :download_uri,
    :anomalies,
    :format,
    :celery_task_id,
    :validations
  ]

  use ExConstructor

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
    validations:    Map.t,
  }
end
