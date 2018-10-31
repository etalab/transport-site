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
    :valid?,
    :frequency,
    :created_at,
    :last_update,
    :metadata,
    :fatal_error,
    :region,
    :commune_principale,
    :import_date,
    :validation_date,
    validations: [],
    tags: [],
  ]

  use ExConstructor

  @type t :: %__MODULE__{
          _id: %BSON.ObjectId{},
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
          valid?: boolean(),
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

  @doc """
  Group by issue type.
  """
  @spec assign(%__MODULE__{}, :group_validations) :: %__MODULE__{}
  def assign(%__MODULE__{} = dataset, :group_validations) do
    validations =
    dataset.validations
    |> Enum.group_by(fn validation -> validation["issue_type"] end)
    |> Map.new(fn {type, issues} -> {type, %{issues: issues, count: Enum.count issues}} end)

    %{dataset | validations: validations}
  end

  @doc """
  Add whether the dataset is valid or no.
  """
  @spec assign(%__MODULE__{}, :valid?) :: %__MODULE__{}
  def assign(%__MODULE__{} = dataset, :valid?) do
    # We have some neptune datasets. Until we know how to handle them,
    # we accept files that won’t be validated
    # new(%{dataset | valid?: dataset.fatal_count == 0})
    new(%{dataset | valid?: true})
  end
end
