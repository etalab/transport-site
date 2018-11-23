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
    :full_logo,
    :spatial,
    :licence,
    :slug,
    :id,
    :download_url,
    :format,
    :frequency,
    :created_at,
    :last_update,
    :metadata,
    :fatal_error,
    :region,
    :commune_principale,
    :import_date,
    :validation_date,
    :type,
    validations: [],
    tags: [],
  ]

  use ExConstructor

  @type t :: %__MODULE__{
          #_id: %BSON.ObjectId{},
          title: String.t(),
          description: String.t(),
          logo: String.t(),
          full_logo: String.t(),
          spatial: String.t(),
          licence: String.t(),
          slug: String.t(),
          download_url: String.t(),
          format: String.t(),
          validations: Map.t(),
          frequency: String.t(),
          created_at: String.t(),
          last_update: String.t(),
          metadata: Map.t(),
          fatal_error: Map.t(),
          tags: [String.t()],
          region: String.t(),
          commune_principale: String.t(),
          import_date: String.t(),
          validation_date: String.t(),
          type: String.t()
        }

  def regions_lookup, do:  %{"$lookup" => %{
        "from" => "datasets",
        "localField" => "properties.NOM_REG",
        "foreignField" => "region",
        "as" => "datasets"
      }}

  def aoms_lookup, do: %{"$lookup" => %{
        "from" => "datasets",
        "localField" => "properties.liste_aom_Code INSEE Commune Principale",
        "foreignField" => "commune_principale",
        "as" => "datasets"
      }}
end
