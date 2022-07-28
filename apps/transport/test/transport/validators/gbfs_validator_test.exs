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

  test "validator_version" do
    sha = setup_validator_version_mocks()

    assert GBFSValidator.validator_version() == sha
  end

  test "inserts the expected data in the database" do
    %DB.Resource{id: resource_id} =
      resource = insert(:resource, url: url = "https://example.com/gbfs.json", format: "gbfs")

    assert DB.Resource.is_gbfs?(resource)

    validator_version = setup_validator_version_mocks()

    Transport.Shared.GBFSMetadata.Mock
    |> expect(:compute_feed_metadata, fn ^url, "https://transport.data.gouv.fr" ->
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
          validator: :validator_module
        },
        has_cors: true,
        is_cors_allowed: true
      }
    end)

    GBFSValidator.validate_and_save(resource)

    assert %DB.MultiValidation{
             metadata: %DB.ResourceMetadata{
               metadata: %{
                 "feeds" => ["system_information", "station_information", "station_status"],
                 "has_cors" => true,
                 "is_cors_allowed" => true,
                 "languages" => ["fr"],
                 "system_details" => %{"name" => "velhop", "timezone" => "Europe/Paris"},
                 "ttl" => 3600,
                 "types" => ["stations"],
                 "versions" => ["1.1"]
               },
               resource_id: ^resource_id
             },
             resource_id: ^resource_id,
             result: %{
               "errors_count" => 0,
               "has_errors" => false,
               "validator" => "validator_module",
               "version_detected" => "1.1",
               "version_validated" => "1.1"
             },
             validated_data_name: ^url,
             validator: "MobilityData/gbfs-validator",
             validator_version: ^validator_version
           } = DB.MultiValidation |> DB.Repo.one!() |> DB.Repo.preload(:metadata)
  end

  defp setup_validator_version_mocks(default_branch \\ "master", sha \\ Ecto.UUID.generate()) do
    Transport.HTTPoison.Mock
    |> expect(:get!, fn "https://api.github.com/repos/MobilityData/gbfs-validator" ->
      %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"default_branch" => default_branch})}
    end)

    commits_url = "https://api.github.com/repos/MobilityData/gbfs-validator/commits/#{default_branch}"

    Transport.HTTPoison.Mock
    |> expect(:get!, fn ^commits_url ->
      %HTTPoison.Response{status_code: 200, body: Jason.encode!(%{"sha" => sha})}
    end)

    sha
  end
end
