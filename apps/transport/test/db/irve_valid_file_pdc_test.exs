defmodule DB.IRVEValidFilePDCTest do
  use ExUnit.Case, async: true
  require Ecto.Query

  doctest DB.IRVEValidFile, import: true
  doctest DB.IRVEValidPDC, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "can bulk insert and retrieve charging point records using factory data" do
    now = DateTime.utc_now()

    file_data = %DB.IRVEValidFile{
      dataset_datagouv_id: "5448d3e0-2bbb-4c97-8687-0c97ace26719",
      resource_datagouv_id: "8b4c0402-8669-4bb9-8124-8e0e4b4f3f39",
      checksum: "abc123def456",
      inserted_at: now,
      updated_at: now
    }

    {:ok, %DB.IRVEValidFile{id: file_id}} =
      DB.Repo.insert(file_data, returning: [:id])

    retrieved_file = DB.Repo.get!(DB.IRVEValidFile, file_id)

    assert retrieved_file.dataset_datagouv_id == "5448d3e0-2bbb-4c97-8687-0c97ace26719"

    factory_data = DB.Factory.IRVE.generate_row()

    pdc_data =
      factory_data
      |> DB.IRVEValidPDC.raw_data_to_schema()
      |> DB.IRVEValidPDC.insert_timestamps()
      |> Map.put(:irve_valid_file_id, file_id)

    # Insert directly using DB.Repo.insert_all
    {1, [%{id: pdc_id}]} =
      DB.Repo.insert_all(DB.IRVEValidPDC, [pdc_data], returning: [:id])

    # Retrieve and verify some key fields
    retrieved_pdc =
      DB.Repo.get!(DB.IRVEValidPDC, pdc_id)
      |> DB.Repo.preload(:irve_valid_file)

    assert retrieved_pdc.id_pdc_itinerance == "FRPAN99E12345678"

    ## Associations work
    assert retrieved_pdc.irve_valid_file == retrieved_file

    retrieved_file = DB.Repo.preload(retrieved_file, :irve_valid_pdcs)
    assert [%DB.IRVEValidPDC{id: ^pdc_id}] = retrieved_file.irve_valid_pdcs
  end

  test "all IRVE static schema fields are present" do
    official_schema_fields = Transport.IRVE.StaticIRVESchema.field_names_list()
    ecto_schema_fields = DB.IRVEValidPDC.__schema__(:fields) |> Enum.map(&Atom.to_string/1)

    assert official_schema_fields -- ["coordonneesXY"] ==
             ecto_schema_fields --
               ["id", "irve_valid_file_id", "inserted_at", "updated_at", "longitude", "latitude"]

    # This test doesn’t test if the optionality of fields is correct
    # as nullable/not nullable is a PostgreSQL constraint added with the migration.
    # It doesn’t check if types are correct neither.
    # That said, in the future, if you’ve updated the schema and found this test failing,
    # feel free to buy me a drink.
  end
end
