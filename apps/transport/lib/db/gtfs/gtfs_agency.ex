defmodule DB.GTFS.Agency do
  @moduledoc """
  This contains the information present in GTFS agency.txt files.
  https://developers.google.com/transit/gtfs/reference?hl=fr#agencytxt
  """
  use Ecto.Schema
  use TypedEctoSchema

  typed_schema "gtfs_agency" do
    belongs_to(:data_import, DB.DataImport)

    field(:agency_id, :binary)
    field(:agency_name, :binary)
    field(:agency_url, :binary)
    field(:agency_timezone, :binary)
    field(:agency_lang, :binary)
    field(:agency_phone, :binary)
    field(:agency_fare_url, :binary)
    field(:agency_email, :binary)
    field(:cemv_support, :integer)
  end
end
