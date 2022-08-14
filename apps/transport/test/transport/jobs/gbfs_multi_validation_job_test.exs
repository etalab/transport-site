defmodule Transport.Test.Transport.Jobs.GBFSMultiValidationDispatcherJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  alias Shared.Validation.GBFSValidator.Summary, as: GBFSValidationSummary
  alias Transport.Jobs.{GBFSMultiValidationDispatcherJob, GBFSMultiValidationJob}

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "relevant_resources" do
    resource = insert(:resource, dataset: insert(:dataset), is_available: true, format: "gbfs")

    _unvailable_resource = insert(:resource, dataset: insert(:dataset), is_available: true, format: "csv")
    _csv_resource = insert(:resource, dataset: insert(:dataset), is_available: false, format: "gbfs")

    assert [resource.id] == GBFSMultiValidationDispatcherJob.relevant_resources()
  end

  test "enqueues other jobs" do
    %DB.Resource{id: resource_id} = insert(:resource, dataset: insert(:dataset), is_available: true, format: "gbfs")

    # Non-relevant resource: a CSV
    insert(:resource, dataset: insert(:dataset), is_available: true, format: "csv")

    assert :ok == perform_job(GBFSMultiValidationDispatcherJob, %{})
    assert [%Oban.Job{args: %{"resource_id" => ^resource_id}}] = all_enqueued(worker: GBFSMultiValidationJob)
  end

  test "validates a GBFS resource" do
    %DB.Resource{id: resource_id, url: url} =
      resource =
      insert(:resource,
        dataset: insert(:dataset),
        is_available: true,
        format: "gbfs",
        url: "https://example.com/gbfs.json"
      )

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

    assert :ok == perform_job(GBFSMultiValidationJob, %{resource_id: resource_id})

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
             command: "https://gbfs-validator.netlify.app/.netlify/functions/validator",
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
