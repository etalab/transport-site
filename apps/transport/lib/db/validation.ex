defmodule DB.Validation do
  @moduledoc """
  Validation model
  """
  use Ecto.Schema
  use TypedEctoSchema
  alias DB.Resource
  import TransportWeb.Gettext, only: [dgettext: 2]

  typed_schema "validations" do
    field(:details, :map)
    # metadatas are stored for performance reasons in the associated resource
    # for on the fly validation, there is no resource, so we store it here
    field(:on_the_fly_validation_metadata, :map)
    field(:date, :string)
    # the maximum level of error in this validation
    field(:max_error, :string)
    # content_hash of the validated resource
    # This makes it possible to check if we need to revalidate the resource
    field(:validation_latest_content_hash, :string)
    field(:data_vis, :map)

    belongs_to(:resource, Resource)
  end

  # All those functions are now duplicated in Transport.Validators.GTFSTransport
  # the ones here will be removed in the future, when migration to the multi validation is complete.
  @spec severities_map() :: map()
  def severities_map,
    do: %{
      "Fatal" => %{level: 0, text: dgettext("gtfs-transport-validator", "Fatal failures")},
      "Error" => %{level: 1, text: dgettext("gtfs-transport-validator", "Errors")},
      "Warning" => %{level: 2, text: dgettext("gtfs-transport-validator", "Warnings")},
      "Information" => %{level: 3, text: dgettext("gtfs-transport-validator", "Informations")},
      "Irrelevant" => %{level: 4, text: dgettext("gtfs-transport-validator", "Passed validations")}
    }

  @spec severities(binary()) :: %{level: integer(), text: binary()}
  def severities(key), do: severities_map()[key]
end
