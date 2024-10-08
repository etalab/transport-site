defmodule Transport.Validators.NeTExTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Mox
  import ExUnit.CaptureLog
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

  @sample_error_message Enum.take(@sample_error_messages, 1)

  describe "existing resource" do
    test "valid NeTEx" do
      {resource, resource_history} = mk_netex_resource()

      validation_id = expect_create_validation()
      expect_successful_validation(validation_id, 12)

      assert :ok == NeTEx.validate_and_save(resource)

      multi_validation = load_multi_validation(resource_history.id)

      assert multi_validation.command == "http://localhost:9999/chouette-valid/#{validation_id}"
      assert multi_validation.validator == "enroute-chouette-netex-validator"
      assert multi_validation.validator_version == "saas-production"
      assert multi_validation.result == %{}
      assert multi_validation.metadata.metadata == %{"retries" => 0, "elapsed_seconds" => 12}
    end

    test "invalid NeTEx" do
      {resource, resource_history} = mk_netex_resource()

      validation_id = expect_create_validation()
      expect_failed_validation(validation_id, 31)

      expect_get_messages(validation_id, @sample_error_messages)

      assert :ok == NeTEx.validate_and_save(resource)

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
                   "criticity" => "warning"
                 }
               ],
               "valid-day-bits" => [
                 %{
                   "code" => "valid-day-bits",
                   "message" => "Mandatory attribute valid_day_bits not found",
                   "criticity" => "warning"
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
                   "criticity" => "warning"
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

      validation_id = expect_create_validation()
      expect_successful_validation(validation_id, 9)

      assert {:ok, %{"validations" => %{}, "metadata" => %{retries: 0, elapsed_seconds: 9}}} ==
               NeTEx.validate(resource_url)
    end

    test "invalid NeTEx" do
      resource_url = mk_raw_netex_resource()

      validation_id = expect_create_validation()
      expect_failed_validation(validation_id, 25)

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
            "criticity" => "warning"
          }
        ],
        "valid-day-bits" => [
          %{
            "code" => "valid-day-bits",
            "message" => "Mandatory attribute valid_day_bits not found",
            "criticity" => "warning"
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
            "criticity" => "warning"
          }
        ]
      }

      assert {:ok, %{"validations" => validation_result, "metadata" => %{retries: 0, elapsed_seconds: 25}}} ==
               NeTEx.validate(resource_url)
    end

    test "retries" do
      resource_url = mk_raw_netex_resource()

      validation_id = expect_create_validation()
      expect_pending_validation(validation_id)
      expect_pending_validation(validation_id)
      expect_pending_validation(validation_id)
      expect_failed_validation(validation_id, 35)

      expect_get_messages(validation_id, @sample_error_message)

      validation_result = %{
        "xsd-1871" => [
          %{
            "code" => "xsd-1871",
            "criticity" => "error",
            "message" =>
              "Element '{http://www.netex.org.uk/netex}OppositeDIrectionRef': This element is not expected. Expected is ( {http://www.netex.org.uk/netex}OppositeDirectionRef )."
          }
        ]
      }

      # Let's disable graceful retry as we are mocking the API, otherwise the
      # test would take almost a minute.
      assert {:ok, %{"validations" => validation_result, "metadata" => %{retries: 3, elapsed_seconds: 35}}} ==
               NeTEx.validate(resource_url, graceful_retry: false)
    end

    test "timeout" do
      resource_url = mk_raw_netex_resource()

      validation_id = expect_create_validation()

      Enum.each(0..100, fn _i ->
        expect_pending_validation(validation_id)
      end)

      {result, log} = with_log(fn -> NeTEx.validate(resource_url, graceful_retry: false) end)

      assert result == {:error, %{message: "enRoute Chouette Valid: Timeout while fetching results", retries: 100}}
      assert log =~ "[error] Timeout while fetching result on enRoute Chouette Valid"
    end
  end

  defp mk_netex_resource do
    dataset = insert(:dataset)

    resource = insert(:resource, dataset_id: dataset.id, format: "NeTEx")

    resource_history =
      insert(:resource_history, resource_id: resource.id, payload: %{"permanent_url" => mk_raw_netex_resource()})

    {resource, resource_history}
  end

  defp mk_raw_netex_resource do
    resource_url = "http://localhost:9999/netex-#{Ecto.UUID.generate()}.zip"

    expect(Transport.Req.Mock, :get!, 1, fn ^resource_url, [{:compressed, false}, {:into, _}] ->
      {:ok, %Req.Response{status: 200, body: %{"data" => "some_zip_file"}}}
    end)

    resource_url
  end
end
