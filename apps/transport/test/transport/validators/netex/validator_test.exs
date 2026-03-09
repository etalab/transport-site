defmodule Transport.Validators.NeTEx.ValidatorTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import Mox
  import Transport.Test.EnRouteChouetteValidClientHelpers

  alias Transport.Validators.NeTEx.ResultsAdapters.V0_2_1, as: ResultsAdapter
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

  describe "existing resource" do
    test "valid NeTEx" do
      start_date = "2025-11-03"
      end_date = "2025-11-15"
      network = "Réseau Urbain"
      modes = ["bus", "ferry"]

      resource_history = mk_netex_resource_with_calendar(start_date, end_date, network, modes)

      validation_id = expect_create_validation("pan:french_profile:1") |> expect_successful_validation(12)

      assert :ok == Validator.validate_and_save(resource_history)

      multi_validation = load_multi_validation(resource_history.id)

      assert multi_validation.command == "http://localhost:9999/chouette-valid/#{validation_id}"
      assert multi_validation.validator == "enroute-chouette-netex-validator"
      assert multi_validation.validator_version == "0.2.1"
      assert multi_validation.result == nil
      assert multi_validation.digest == ResultsAdapter.digest(%{})
      assert multi_validation.binary_result == ResultsAdapter.to_binary_result(%{})

      assert multi_validation.metadata.metadata == %{
               "retries" => 0,
               "elapsed_seconds" => 12,
               "start_date" => start_date,
               "end_date" => end_date,
               "networks" => [network],
               "modes" => modes
             }

      assert multi_validation.metadata.modes == modes
    end

    test "pending validation" do
      start_date = "2025-11-03"
      end_date = "2025-11-15"
      network = "Réseau Urbain"
      modes = ["bus", "ferry"]

      resource_history = mk_netex_resource_with_calendar(start_date, end_date, network, modes)

      validation_id = expect_create_validation("pan:french_profile:1") |> expect_pending_validation()

      assert :ok == Validator.validate_and_save(resource_history)

      assert_enqueued(
        worker: Transport.Jobs.NeTExPollerJob,
        args: %{
          "validation_id" => validation_id,
          "resource_history_id" => resource_history.id,
          "metadata" => %{"start_date" => start_date, "end_date" => end_date, "networks" => [network], "modes" => modes}
        }
      )

      assert nil == load_multi_validation(resource_history.id)
    end

    test "invalid NeTEx" do
      start_date = "2025-11-03"
      end_date = "2025-11-15"
      network = "Réseau Urbain"
      modes = ["bus", "ferry"]

      resource_history = mk_netex_resource_with_calendar(start_date, end_date, network, modes)

      validation_id = expect_create_validation("pan:french_profile:1") |> expect_failed_validation(31)

      expect_get_messages(validation_id, @sample_error_messages)

      assert :ok == Validator.validate_and_save(resource_history)

      multi_validation = load_multi_validation(resource_history.id)

      assert multi_validation.command == "http://localhost:9999/chouette-valid/#{validation_id}/messages"
      assert multi_validation.validator == "enroute-chouette-netex-validator"
      assert multi_validation.validator_version == "0.2.1"

      assert multi_validation.metadata.metadata == %{
               "retries" => 0,
               "elapsed_seconds" => 31,
               "start_date" => start_date,
               "end_date" => end_date,
               "networks" => [network],
               "modes" => modes
             }

      assert multi_validation.metadata.modes == modes

      result = %{
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

      assert multi_validation.result == nil

      assert multi_validation.digest == ResultsAdapter.digest(result)
      assert multi_validation.binary_result == ResultsAdapter.to_binary_result(result)
    end

    defp load_multi_validation(resource_history_id) do
      DB.MultiValidation.base_query(include_binary_result: true)
      |> DB.Repo.get_by(resource_history_id: resource_history_id)
      |> DB.Repo.preload(:metadata)
    end
  end

  describe "raw URL" do
    test "valid NeTEx" do
      start_date = "2025-11-03"
      end_date = "2025-11-15"
      network = "Réseau Urbain"
      modes = ["bus", "ferry"]

      resource_url = mk_netex(start_date, end_date, network, modes)

      expect_create_validation("pan:french_profile:1") |> expect_successful_validation(9)

      assert {:ok,
              %{
                "validations" => %{},
                "metadata" => %{
                  :retries => 0,
                  :elapsed_seconds => 9,
                  "start_date" => start_date,
                  "end_date" => end_date,
                  "networks" => [network],
                  "modes" => modes
                }
              }} ==
               Validator.validate(resource_url)
    end

    test "invalid NeTEx" do
      start_date = "2025-11-03"
      end_date = "2025-11-15"
      network = "Réseau Urbain"
      modes = ["bus", "ferry"]

      resource_url = mk_netex(start_date, end_date, network, modes)

      validation_id = expect_create_validation("pan:french_profile:1") |> expect_failed_validation(25)

      expect_get_messages(validation_id, @sample_error_messages)

      validation_result = %{
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

      assert {:ok,
              %{
                "validations" => validation_result,
                "metadata" => %{
                  :retries => 0,
                  :elapsed_seconds => 25,
                  "start_date" => start_date,
                  "end_date" => end_date,
                  "networks" => [network],
                  "modes" => modes
                }
              }} ==
               Validator.validate(resource_url)
    end

    test "pending" do
      start_date = "2025-11-03"
      end_date = "2025-11-15"
      network = "Réseau Urbain"
      modes = ["bus", "ferry"]

      metadata = %{"start_date" => start_date, "end_date" => end_date, "networks" => [network], "modes" => modes}

      resource_url = mk_netex(start_date, end_date, network, modes)

      validation_id = expect_create_validation("pan:french_profile:1") |> expect_pending_validation()

      assert {:pending, {validation_id, metadata}} == Validator.validate(resource_url)
    end
  end

  defp mk_netex_resource_with_calendar(start_date, end_date, network, modes) do
    dataset = insert(:dataset)

    resource = insert(:resource, dataset_id: dataset.id, format: "NeTEx")

    insert(:resource_history,
      resource_id: resource.id,
      payload: %{"permanent_url" => mk_netex(start_date, end_date, network, modes)}
    )
  end

  defp mk_netex(start_date, end_date, network, modes),
    do:
      mk_raw_netex_resource([
        {"resource.xml", calendar_content(start_date, end_date)},
        {"network.xml", network_content(network, modes)}
      ])

  defp mk_raw_netex_resource(content) do
    resource_url = generate_resource_url()

    expect(Transport.Req.Mock, :get!, 1, fn ^resource_url, [{:compressed, false}, {:into, into}] ->
      content = zip_file(into.path, content)

      {:ok, %Req.Response{status: 200, body: %{"data" => content}}}
    end)

    resource_url
  end

  defp zip_file(path, content) do
    ZipCreator.create!(path, content)
    File.read!(path)
  end

  defp generate_resource_url do
    "http://localhost:9999/netex-#{Ecto.UUID.generate()}.zip"
  end

  defp calendar_content(start_date, end_date) do
    """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" xmlns:gis="http://www.opengis.net/gml/3.2" xmlns:siri="http://www.siri.org.uk/siri" version="1.1:FR-NETEX_CALENDRIER-2.2">
        <PublicationTimestamp>2025-07-29T09:34:55Z</PublicationTimestamp>
        <ParticipantRef>DIGO</ParticipantRef>
        <dataObjects>
          <GeneralFrame version="any" id="DIGO:GeneralFrame:NETEX_CALENDRIER-20250729093455Z:LOC">
            <ValidBetween>
              <FromDate>#{start_date}T00:00:00</FromDate>
              <ToDate>#{end_date}T23:59:59</ToDate>
            </ValidBetween>
          </GeneralFrame>
        </dataObjects>
      </PublicationDelivery>
    """
  end

  defp network_content(network_name, transport_modes) do
    lines =
      Enum.map(transport_modes, fn mode ->
        """
          <Line>
            <TransportMode>#{mode}</TransportMode>
          </Line>
          <Line>
            <TransportMode>#{mode}</TransportMode>
          </Line>
        """
      end)

    """
      <PublicationDelivery xmlns="http://www.netex.org.uk/netex" xmlns:gis="http://www.opengis.net/gml/3.2" xmlns:siri="http://www.siri.org.uk/siri" version="1.1:FR-NETEX_CALENDRIER-2.2">
        <PublicationTimestamp>2025-07-29T09:34:55Z</PublicationTimestamp>
        <ParticipantRef>DIGO</ParticipantRef>
        <dataObjects>
          <GeneralFrame version="any" id="DIGO:GeneralFrame:NETEX_CALENDRIER-20250729093455Z:LOC">
            <members>
              <Network>
                <Name>#{network_name}</Name>
              </Network>
              #{lines}
            </members>
          </GeneralFrame>
        </dataObjects>
      </PublicationDelivery>
    """
  end
end
