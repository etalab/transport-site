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
    title:          String.t,
    description:    String.t,
    logo:           String.t,
    spatial:        String.t,
    license:        String.t,
    slug:           String.t,
    download_uri:   String.t,
    anomalies:      [String.t],
    format:         String.t,
    celery_task_id: String.t,
  }

  @doc """
  Initialises a licence struct from a given map. Map's keys must be strings.

  ## Examples

      iex> Dataset.new(%{"title" => "Dataset"})
      %Dataset{title: "Dataset"}

  """
  @spec new(map()) :: %__MODULE__{}
  def new(%{} = map) do
    Enum.reduce(map, %__MODULE__{}, fn({key, value}, map) ->
      Map.put(map, String.to_existing_atom(key), value)
    end)
  end
end
