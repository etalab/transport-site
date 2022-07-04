defmodule Shared.Validation.TableSchemaValidatorTest do
  use Shared.CacheCase
  import Transport.Shared.Schemas, only: [schema_url: 2]
  import Shared.Validation.TableSchemaValidator

  @schema_name "etalab/schema-lieux-covoiturage"
  @url "https://example.com/file"

  setup do
    Mox.stub_with(Transport.Shared.Schemas.Mock, Transport.Shared.Schemas)
    :ok
  end

  describe "validator_api_url" do
    test "with a specific schema version" do
      setup_schemas_response()
      schema_version = "0.2.2"
      query = URI.encode_query(%{schema: schema_url(@schema_name, schema_version), url: @url})
      expected_url = "https://validata-api.app.etalab.studio/validate?#{query}"

      assert validator_api_url(@schema_name, @url, schema_version) == expected_url
    end

    test "with latest version" do
      setup_schemas_response()
      query = URI.encode_query(%{schema: schema_url(@schema_name, "latest"), url: @url})
      expected_url = "https://validata-api.app.etalab.studio/validate?#{query}"

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
                 "Colonne obligatoire manquante : La colonne obligatoire `siren_amenageur` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `contact_amenageur` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `contact_operateur` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `nom_enseigne` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `id_station_itinerance` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `nom_station` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `implantation_station` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `adresse_station` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `code_insee_commune` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `coordonneesXY` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `id_pdc_itinerance` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `puissance_nominale` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `prise_type_ef` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `prise_type_2` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `prise_type_combo_ccs` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `prise_type_chademo` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `prise_type_autre` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `gratuit` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `paiement_acte` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `paiement_cb` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `paiement_autre` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `condition_acces` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `reservation` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `horaires` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `accessibilite_pmr` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `restriction_gabarit` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `station_deux_roues` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `raccordement` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `num_pdl` est manquante.",
                 "Colonne obligatoire manquante : La colonne obligatoire `date_mise_en_service` est manquante.",
                 "Format de date incorrect : colonne date_maj, ligne 2. La date doit être écrite sous la forme `aaaa-mm-jj`.",
                 "Format de date incorrect : colonne date_maj, ligne 3. La date doit être écrite sous la forme `aaaa-mm-jj`."
               ],
               "errors_count" => 32,
               "has_errors" => true,
               "validator" => Shared.Validation.TableSchemaValidator,
               "validata_api_version" => "0.6.1"
             } == validate(@schema_name, @url)
    end

    test "valid object" do
      setup_schemas_response()
      "validata_with_no_errors.json" |> setup_validata_response()

      assert %{
               "errors" => [],
               "errors_count" => 0,
               "has_errors" => false,
               "validator" => Shared.Validation.TableSchemaValidator,
               "validata_api_version" => "0.6.1"
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
                 "Horaires d'ouverture incorrects : colonne horaires, ligne 2. La valeur 'lundi à dimanche' n'est pas une définition d'horaire d'ouverture correcte.\n\n Celle-ci doit respecter la spécification [OpenStreetMap](https://wiki.openstreetmap.org/wiki/Key:opening_hours) de description d'horaires d'ouverture."
               ],
               "errors_count" => 1,
               "has_errors" => true,
               "validator" => Shared.Validation.TableSchemaValidator,
               "validata_api_version" => "0.6.1"
             } == validate(@schema_name, @url)
    end

    test "when the custom check is unknown and stats.errors is wrong" do
      setup_schemas_response()
      "validata_unknown_custom_check_error.json" |> setup_validata_response()

      assert %{
               "errors" => [
                 "Check Error : colonne , ligne . Check is not valid: 'french_gps_coordinates': custom check inconnu."
               ],
               "errors_count" => 1,
               "has_errors" => true,
               "validator" => Shared.Validation.TableSchemaValidator,
               "validata_api_version" => "0.6.1"
             } == validate(@schema_name, @url)
    end
  end

  defp setup_validata_response(filename), do: filename |> read_json() |> validata_response_with_body()

  defp read_json(filename), do: File.read!("#{__DIR__}/../fixtures/#{filename}")

  defp validata_response_with_body(body, status_code \\ 200) do
    query = URI.encode_query(%{schema: schema_url(@schema_name, "latest"), url: @url})
    url = "https://validata-api.app.etalab.studio/validate?#{query}"

    Transport.HTTPoison.Mock
    |> expect(:get, fn ^url, [] ->
      {:ok, %HTTPoison.Response{body: body, status_code: status_code}}
    end)
  end

  defp setup_schemas_response do
    url = "https://schema.data.gouv.fr/schemas.json"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^url ->
      %HTTPoison.Response{body: File.read!("#{__DIR__}/../fixtures/schemas.json"), status_code: 200}
    end)
  end
end
