defmodule Transport.Validators.GBFSValidatorTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary
  alias Transport.Validators.GBFSValidator

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  test "validate_and_save inserts the expected data in the database" do
    %DB.Resource{id: resource_id} =
      resource = insert(:resource, url: url = "https://example.com/gbfs.json", format: "gbfs")

    assert DB.Resource.is_gbfs?(resource)

    Transport.Shared.GBFSMetadata.Mock
    |> expect(:compute_feed_metadata, fn ^url, "https://www.example.com" ->
      %{
        languages: ["fr"],
        system_details: %{name: "velhop", timezone: "Europe/Paris"},
        ttl: 3600,
        types: ["stations"],
        versions: ["1.1"],
        feeds: ["system_information", "station_information", "station_status"],
        validation: %GBFSValidationSummary{
          errors_count: 0,
          has_errors: false,
          version_detected: "1.1",
          version_validated: "1.1",
          validator_version: "31c5325",
          validator: :validator_module
        },
        cors_header_value: "*"
      }
    end)

    GBFSValidator.validate_and_save(resource)

    assert %DB.MultiValidation{
             metadata: %DB.ResourceMetadata{
               metadata: %{
                 "feeds" => ["system_information", "station_information", "station_status"],
                 "cors_header_value" => "*",
                 "languages" => ["fr"],
                 "system_details" => %{"name" => "velhop", "timezone" => "Europe/Paris"},
                 "ttl" => 3600,
                 "types" => ["stations"],
                 "versions" => ["1.1"]
               },
               resource_id: ^resource_id
             },
             resource_id: ^resource_id,
             result:
               validation_result = %{
                 "errors_count" => 0,
                 "has_errors" => false,
                 "validator" => "validator_module",
                 "version_detected" => "1.1",
                 "version_validated" => "1.1"
               },
             validated_data_name: ^url,
             command: "https://gbfs-validator.netlify.app/.netlify/functions/validator",
             validator: "MobilityData/gbfs-validator",
             validator_version: "31c5325"
           } = DB.MultiValidation |> DB.Repo.one!() |> DB.Repo.preload(:metadata)

    refute Map.has_key?(validation_result, "validator_version")
  end
end
