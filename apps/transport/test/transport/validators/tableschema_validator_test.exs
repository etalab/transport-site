defmodule Transport.Validators.TableSchemaTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  import Transport.Shared.Schemas, only: [schema_url: 2]
  import Transport.Validators.TableSchema
  alias Transport.Validators.TableSchema

  @schema_name "etalab/schema-lieux-covoiturage"
  @url "https://example.com/file"

  doctest Transport.Validators.TableSchema, import: true

  setup do
    Mox.stub_with(Transport.Shared.Schemas.Mock, Transport.Shared.Schemas)
    Cachex.clear(Shared.Application.cache_name())
    on_exit(fn -> Cachex.clear(Shared.Application.cache_name()) end)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "inserts the expected data in the database" do
    %{id: resource_history_id} =
      resource_history =
      insert(:resource_history,
        payload: %{
          "permanent_url" => permanent_url = "https://example.com/permanent",
          "schema_name" => schema_name = "etalab/schema-lieux-covoiturage",
          "schema_version" => schema_version = "0.4.2"
        }
      )

    expected_command_url = setup_mock_validator_url(schema_name, permanent_url, schema_version)
    validator_version = "0.13.37"

    Transport.Validators.TableSchema.Mock
    |> expect(:validate, fn ^schema_name, ^permanent_url, ^schema_version ->
      %{
        "has_errors" => false,
        "errors_count" => 0,
        "errors" => [],
        "validata_api_version" => validator_version,
        "validator" => "OriginalValidatorName"
      }
    end)

    assert :ok == TableSchema.validate_and_save(resource_history)

    assert %{
             result: %{"has_errors" => false, "errors_count" => 0, "errors" => [], "validation_performed" => true},
             digest: %{"errors_count" => 0},
             resource_history_id: ^resource_history_id,
             command: ^expected_command_url,
             data_vis: nil,
             validation_timestamp: _,
             validator: "validata-api",
             validator_version: ^validator_version
           } = DB.MultiValidation.with_result() |> DB.Repo.get_by!(resource_history_id: resource_history_id)
  end

  test "when validator returns nil" do
    %{id: resource_history_id} =
      resource_history =
      insert(:resource_history,
        payload: %{
          "permanent_url" => permanent_url = "https://example.com/permanent",
          "schema_name" => schema_name = "etalab/schema-lieux-covoiturage",
          "schema_version" => nil,
          "latest_schema_version_to_date" => schema_version = "0.4.2"
        }
      )

    expected_command_url = setup_mock_validator_url(schema_name, permanent_url, schema_version)

    Transport.Validators.TableSchema.Mock
    |> expect(:validate, fn ^schema_name, ^permanent_url, ^schema_version -> nil end)

    assert :ok == TableSchema.validate_and_save(resource_history)

    assert %{
             result: %{"validation_performed" => false},
             resource_history_id: ^resource_history_id,
             command: ^expected_command_url,
             data_vis: nil,
             validation_timestamp: _,
             validator: "validata-api",
             validator_version: nil
           } =
             DB.MultiValidation.with_result()
             |> DB.Repo.get_by!(resource_history_id: resource_history_id)
  end

  def setup_mock_validator_url(schema_name, url, schema_version) do
    fake_url = "https://example.com/" <> Enum.join([schema_name, url, schema_version], "/")

    Transport.Validators.TableSchema.Mock
    |> expect(:validator_api_url, fn ^schema_name, ^url, ^schema_version -> fake_url end)

    fake_url
  end

  describe "validator_api_url" do
    test "with a specific schema version" do
      setup_schemas_response()
      schema_version = "0.2.2"
      query = URI.encode_query(%{schema: schema_url(@schema_name, schema_version), url: @url, header_case: "false"})
      expected_url = "https://api.validata.etalab.studio/validate?#{query}"

      assert validator_api_url(@schema_name, @url, schema_version) == expected_url
    end

    test "with latest version" do
      setup_schemas_response()
      query = URI.encode_query(%{schema: schema_url(@schema_name, "latest"), url: @url, header_case: "false"})
      expected_url = "https://api.validata.etalab.studio/validate?#{query}"

      assert validator_api_url(@schema_name, @url) == expected_url
    end
  end

  describe "validate" do
    test "ensures schema is a tableschema" do
      schema_name = "foo"

      assert_raise RuntimeError, "#{schema_name} is not a tableschema", fn ->
        setup_schemas_response()
        validate(schema_name, @url)
      end
    end

    test "invalid object" do
      setup_schemas_response()
      "validata_with_errors.json" |> setup_validata_response()

      assert %{
               "errors" => [
                 "La colonne obligatoire `contact_operateur` est manquante",
                 "La colonne obligatoire `nom_enseigne` est manquante",
                 "La colonne obligatoire `id_station_itinerance` est manquante",
                 "La colonne obligatoire `nom_station` est manquante",
                 "La colonne obligatoire `implantation_station` est manquante",
                 "La colonne obligatoire `adresse_station` est manquante",
                 "La colonne obligatoire `coordonneesXY` est manquante",
                 "La colonne obligatoire `id_pdc_itinerance` est manquante",
                 "La colonne obligatoire `puissance_nominale` est manquante",
                 "La colonne obligatoire `prise_type_ef` est manquante",
                 "La colonne obligatoire `prise_type_2` est manquante",
                 "La colonne obligatoire `prise_type_combo_ccs` est manquante",
                 "La colonne obligatoire `prise_type_chademo` est manquante",
                 "La colonne obligatoire `prise_type_autre` est manquante",
                 "La colonne obligatoire `paiement_acte` est manquante",
                 "La colonne obligatoire `condition_acces` est manquante",
                 "La colonne obligatoire `reservation` est manquante",
                 "La colonne obligatoire `horaires` est manquante",
                 "La colonne obligatoire `accessibilite_pmr` est manquante",
                 "La colonne obligatoire `restriction_gabarit` est manquante",
                 "La colonne obligatoire `station_deux_roues` est manquante",
                 "La date doit être écrite sous la forme `aaaa-mm-jj` Colonne `date_maj`, ligne 2.",
                 "La date doit être écrite sous la forme `aaaa-mm-jj` Colonne `date_maj`, ligne 3."
               ],
               "errors_count" => 23,
               "has_errors" => true,
               "validata_api_version" => "0.12.0",
               "validator" => Transport.Validators.TableSchema
             } == validate(@schema_name, @url)
    end

    test "valid object" do
      setup_schemas_response()
      "validata_with_no_errors.json" |> setup_validata_response()

      assert %{
               "errors" => [],
               "errors_count" => 0,
               "has_errors" => false,
               "validator" => Transport.Validators.TableSchema,
               "validata_api_version" => "0.12.0"
             } == validate(@schema_name, @url)
    end

    test "with a server error" do
      setup_schemas_response()
      validata_response_with_body("error", 500)
      assert nil == validate(@schema_name, @url)
    end

    test "with a file error" do
      setup_schemas_response()
      "validata_with_file_error.json" |> setup_validata_response()

      assert nil == validate(@schema_name, @url)
    end

    test "with a custom check error" do
      setup_schemas_response()
      "validata_with_opening_hours_error.json" |> setup_validata_response()

      assert %{
               "errors" => [
                 "La valeur 'lundi à dimanche' n'est pas une définition d'horaire d'ouverture correcte.\n\n Celle-ci doit respecter la spécification [OpenStreetMap](https://wiki.openstreetmap.org/wiki/Key:opening_hours) de description d'horaires d'ouverture. Colonne `horaires`, ligne 2."
               ],
               "errors_count" => 1,
               "has_errors" => true,
               "validator" => Transport.Validators.TableSchema,
               "validata_api_version" => "0.12.0"
             } == validate(@schema_name, @url)
    end

    test "when the custom check is unknown and stats.errors is wrong" do
      setup_schemas_response()
      "validata_unknown_custom_check_error.json" |> setup_validata_response()

      assert %{
               "errors" => [
                 "Tentative de définir le custom check 'french_gps_coordinates', qui n'est pas connu."
               ],
               "errors_count" => 1,
               "has_errors" => true,
               "validator" => Transport.Validators.TableSchema,
               "validata_api_version" => "0.12.0"
             } == validate(@schema_name, @url)
    end

    test "when the remote file does not exist" do
      setup_schemas_response()
      "validata_source_error.json" |> setup_validata_response()
      assert :source_error == validate(@schema_name, @url)
    end
  end

  describe "validata_web_url" do
    test "it works" do
      setup_schemas_response()

      assert "https://validata.fr/table-schema?schema_name=schema-datagouvfr.etalab%2Fschema-lieux-covoiturage" ==
               validata_web_url(@schema_name)
    end

    test "with an unknown schema" do
      schema_name = "foo"

      assert_raise RuntimeError, "#{schema_name} is not a tableschema", fn ->
        setup_schemas_response()
        validata_web_url(schema_name)
      end
    end
  end

  defp setup_validata_response(filename), do: filename |> read_json() |> validata_response_with_body()

  defp read_json(filename), do: File.read!("#{__DIR__}/../../fixture/schemas/#{filename}")

  defp validata_response_with_body(body, status_code \\ 200) do
    query = URI.encode_query(%{schema: schema_url(@schema_name, "latest"), url: @url, header_case: "false"})
    url = "https://api.validata.etalab.studio/validate?#{query}"

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [] = _headers, [recv_timeout: 180_000] = _options ->
      {:ok, %HTTPoison.Response{body: body, status_code: status_code}}
    end)
  end

  defp setup_schemas_response do
    url = "https://schema.data.gouv.fr/schemas.json"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url ->
      %HTTPoison.Response{body: File.read!("#{__DIR__}/../../fixture/schemas/schemas.json"), status_code: 200}
    end)
  end
end
