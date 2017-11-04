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
    :license,
    :slug,
    :download_uri,
    :anomalies,
    :format,
    :celery_task_id
  ]

  @type t :: %__MODULE__{
    _id:            %BSON.ObjectId{},
    title:          String.t | nil,
    description:    String.t | nil,
    logo:           String.t | nil,
    spatial:        String.t | nil,
    license:        String.t | nil,
    slug:           String.t | nil,
    download_uri:   String.t | nil,
    anomalies:      [String.t],
    format:         String.t | nil,
    celery_task_id: String.t | nil,
  }
end
