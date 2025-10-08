defmodule Transport.Jobs.NeTExPollerJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import ExUnit.CaptureLog
  import Mox
  import Transport.Test.EnRouteChouetteValidClientHelpers

  alias Transport.Validators.NeTEx.Validator

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  setup :verify_on_exit!

  @sample_error_messages [
    %{
      "code" => "xsd-1871",
      "criticity" => "error",
      "message" =>
        "Element '{http://www.netex.org.uk/netex}OppositeDIrectionRef': This element is not expected. Expected is ( {http://www.netex.org.uk/netex}OppositeDirectionRef )."
    },
    %{
      "code" => "uic-operating-period",
      "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
      "criticity" => "error"
    },
    %{
      "code" => "valid-day-bits",
      "message" => "Mandatory attribute valid_day_bits not found",
      "criticity" => "error"
    },
    %{
      "code" => "frame-arret-resources",
      "message" => "Tag frame_id doesn't match ''",
      "criticity" => "warning"
    },
    %{
      "message" => "Reference MOBIITI:Quay:104325 doesn't match any existing Resource",
      "criticity" => "error"
    }
  ]

  test "valid NeTEx" do
    resource_history = generate_resource_url() |> mk_netex_resource()

    attempts = 5
    duration = 12

    validation_id = with_running_validation() |> expect_successful_validation(duration)

    assert :ok == run_polling_job(resource_history, validation_id, attempts)

    multi_validation = load_multi_validation(resource_history.id)

    assert multi_validation.command == "http://localhost:9999/chouette-valid/#{validation_id}"
    assert multi_validation.validator == "enroute-chouette-netex-validator"
    assert multi_validation.validator_version == "0.2.0"
    assert multi_validation.result == %{}
    assert multi_validation.metadata.metadata == %{"retries" => attempts, "elapsed_seconds" => duration}
  end

  test "invalid NeTEx" do
    resource_history = generate_resource_url() |> mk_netex_resource()

    attempts = 5
    duration = 12

    validation_id = with_running_validation() |> expect_failed_validation(duration)

    expect_get_messages(validation_id, @sample_error_messages)

    assert :ok = run_polling_job(resource_history, validation_id, attempts)

    multi_validation = load_multi_validation(resource_history.id)

    assert multi_validation.command == "http://localhost:9999/chouette-valid/#{validation_id}/messages"
    assert multi_validation.validator == "enroute-chouette-netex-validator"
    assert multi_validation.validator_version == "0.2.0"
    assert multi_validation.metadata.metadata == %{"retries" => attempts, "elapsed_seconds" => duration}

    assert multi_validation.result == %{
             "xsd-schema" => [
               %{
                 "code" => "xsd-1871",
                 "criticity" => "error",
                 "message" =>
                   "Element '{http://www.netex.org.uk/netex}OppositeDIrectionRef': This element is not expected. Expected is ( {http://www.netex.org.uk/netex}OppositeDirectionRef )."
               }
             ],
             "base-rules" => [
               %{
                 "code" => "uic-operating-period",
                 "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
                 "criticity" => "error"
               },
               %{
                 "code" => "valid-day-bits",
                 "message" => "Mandatory attribute valid_day_bits not found",
                 "criticity" => "error"
               },
               %{
                 "code" => "frame-arret-resources",
                 "message" => "Tag frame_id doesn't match ''",
                 "criticity" => "warning"
               },
               %{
                 "message" => "Reference MOBIITI:Quay:104325 doesn't match any existing Resource",
                 "criticity" => "error"
               }
             ]
           }
  end

  test "pending validation" do
    resource_history = generate_resource_url() |> mk_netex_resource()

    attempt = 5

    validation_id = with_running_validation() |> expect_pending_validation()

    assert {:snooze, Validator.poll_interval(attempt)} == run_polling_job(resource_history, validation_id, attempt)

    assert nil == load_multi_validation(resource_history.id)
  end

  test "too many attempts" do
    resource_history = generate_resource_url() |> mk_netex_resource()

    attempt = 181

    validation_id = with_running_validation() |> expect_pending_validation()

    capture_log([level: :error], fn ->
      assert :ok = run_polling_job(resource_history, validation_id, attempt)

      assert nil == load_multi_validation(resource_history.id)
    end) =~ "Timeout while fetching results on enRoute Chouette Valid (resource_history_id: #{resource_history.id})"
  end

  defp load_multi_validation(resource_history_id) do
    DB.MultiValidation.with_result()
    |> DB.Repo.get_by(resource_history_id: resource_history_id)
    |> DB.Repo.preload(:metadata)
  end

  defp mk_netex_resource(permanent_url) do
    dataset = insert(:dataset)

    resource = insert(:resource, dataset_id: dataset.id, format: "NeTEx")

    insert(:resource_history, resource_id: resource.id, payload: %{"permanent_url" => permanent_url})
  end

  defp generate_resource_url do
    "http://localhost:9999/netex-#{Ecto.UUID.generate()}.zip"
  end

  defp run_polling_job(%DB.ResourceHistory{} = resource_history, validation_id, attempt) do
    payload =
      %{
        "resource_history_id" => resource_history.id,
        "validation_id" => validation_id
      }

    perform_job(Transport.Jobs.NeTExPollerJob, payload, attempt: attempt)
  end
end
