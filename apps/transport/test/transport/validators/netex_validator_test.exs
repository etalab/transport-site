defmodule Transport.Validators.NeTExTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Transport.Test.EnRouteChouetteValidClientHelpers

  alias Transport.Validators.NeTEx

  doctest Transport.Validators.NeTEx, import: true

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

  describe "existing resource" do
    test "valid NeTEx" do
      resource_history = mk_netex_resource()

      validation_id = expect_create_validation() |> expect_successful_validation(12)

      assert :ok == NeTEx.validate_and_save(resource_history)

      multi_validation = load_multi_validation(resource_history.id)

      assert multi_validation.command == "http://localhost:9999/chouette-valid/#{validation_id}"
      assert multi_validation.validator == "enroute-chouette-netex-validator"
      assert multi_validation.validator_version == "saas-production"
      assert multi_validation.result == %{}
      assert multi_validation.metadata.metadata == %{"retries" => 0, "elapsed_seconds" => 12}
    end

    test "pending validation" do
      resource_history = mk_netex_resource()

      validation_id = expect_create_validation() |> expect_pending_validation()

      assert :ok == NeTEx.validate_and_save(resource_history)

      assert_enqueued(
        worker: Transport.Jobs.NeTExPollerJob,
        args: %{
          "validation_id" => validation_id,
          "resource_history_id" => resource_history.id
        }
      )

      assert nil == load_multi_validation(resource_history.id)
    end

    test "invalid NeTEx" do
      resource_history = mk_netex_resource()

      validation_id = expect_create_validation() |> expect_failed_validation(31)

      expect_get_messages(validation_id, @sample_error_messages)

      assert :ok == NeTEx.validate_and_save(resource_history)

      multi_validation = load_multi_validation(resource_history.id)

      assert multi_validation.command == "http://localhost:9999/chouette-valid/#{validation_id}/messages"
      assert multi_validation.validator == "enroute-chouette-netex-validator"
      assert multi_validation.validator_version == "saas-production"
      assert multi_validation.metadata.metadata == %{"retries" => 0, "elapsed_seconds" => 31}

      assert multi_validation.result == %{
               "xsd-1871" => [
                 %{
                   "code" => "xsd-1871",
                   "criticity" => "error",
                   "message" =>
                     "Element '{http://www.netex.org.uk/netex}OppositeDIrectionRef': This element is not expected. Expected is ( {http://www.netex.org.uk/netex}OppositeDirectionRef )."
                 }
               ],
               "uic-operating-period" => [
                 %{
                   "code" => "uic-operating-period",
                   "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
                   "criticity" => "error"
                 }
               ],
               "valid-day-bits" => [
                 %{
                   "code" => "valid-day-bits",
                   "message" => "Mandatory attribute valid_day_bits not found",
                   "criticity" => "error"
                 }
               ],
               "frame-arret-resources" => [
                 %{
                   "code" => "frame-arret-resources",
                   "message" => "Tag frame_id doesn't match ''",
                   "criticity" => "warning"
                 }
               ],
               "unknown-code" => [
                 %{
                   "message" => "Reference MOBIITI:Quay:104325 doesn't match any existing Resource",
                   "criticity" => "error"
                 }
               ]
             }
    end

    defp load_multi_validation(resource_history_id) do
      DB.MultiValidation
      |> DB.Repo.get_by(resource_history_id: resource_history_id)
      |> DB.Repo.preload(:metadata)
    end
  end

  describe "raw URL" do
    test "valid NeTEx" do
      resource_url = mk_raw_netex_resource()

      expect_create_validation() |> expect_successful_validation(9)

      assert {:ok, %{"validations" => %{}, "metadata" => %{retries: 0, elapsed_seconds: 9}}} ==
               NeTEx.validate(resource_url)
    end

    test "invalid NeTEx" do
      resource_url = mk_raw_netex_resource()

      validation_id = expect_create_validation() |> expect_failed_validation(25)

      expect_get_messages(validation_id, @sample_error_messages)

      validation_result = %{
        "xsd-1871" => [
          %{
            "code" => "xsd-1871",
            "criticity" => "error",
            "message" =>
              "Element '{http://www.netex.org.uk/netex}OppositeDIrectionRef': This element is not expected. Expected is ( {http://www.netex.org.uk/netex}OppositeDirectionRef )."
          }
        ],
        "uic-operating-period" => [
          %{
            "code" => "uic-operating-period",
            "message" => "Resource 23504000009 hasn't expected class but Netex::OperatingPeriod",
            "criticity" => "error"
          }
        ],
        "valid-day-bits" => [
          %{
            "code" => "valid-day-bits",
            "message" => "Mandatory attribute valid_day_bits not found",
            "criticity" => "error"
          }
        ],
        "frame-arret-resources" => [
          %{
            "code" => "frame-arret-resources",
            "message" => "Tag frame_id doesn't match ''",
            "criticity" => "warning"
          }
        ],
        "unknown-code" => [
          %{
            "message" => "Reference MOBIITI:Quay:104325 doesn't match any existing Resource",
            "criticity" => "error"
          }
        ]
      }

      assert {:ok, %{"validations" => validation_result, "metadata" => %{retries: 0, elapsed_seconds: 25}}} ==
               NeTEx.validate(resource_url)
    end

    test "pending" do
      resource_url = mk_raw_netex_resource()

      validation_id = expect_create_validation() |> expect_pending_validation()

      assert {:pending, validation_id} == NeTEx.validate(resource_url)
    end
  end

  defp mk_netex_resource do
    dataset = insert(:dataset)

    resource = insert(:resource, dataset_id: dataset.id, format: "NeTEx")

    insert(:resource_history, resource_id: resource.id, payload: %{"permanent_url" => mk_raw_netex_resource()})
  end

  defp mk_raw_netex_resource do
    resource_url = generate_resource_url()

    expect(Transport.Req.Mock, :get!, 1, fn ^resource_url, [{:compressed, false}, {:into, _}] ->
      {:ok, %Req.Response{status: 200, body: %{"data" => "some_zip_file"}}}
    end)

    resource_url
  end

  defp generate_resource_url do
    "http://localhost:9999/netex-#{Ecto.UUID.generate()}.zip"
  end
end
