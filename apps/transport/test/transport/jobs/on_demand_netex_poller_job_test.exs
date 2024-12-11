defmodule Transport.Test.Transport.Jobs.OnDemandNeTExPollerJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import DB.Factory
  import ExUnit.CaptureLog
  import Mox
  import Transport.Test.EnRouteChouetteValidClientHelpers
  alias Transport.Validators.NeTEx

  setup :verify_on_exit!

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  @filename "file.zip"

  test "still pending" do
    attempt = 1
    validation = create_validation(%{"type" => "netex"})

    validation_id = with_running_validation() |> expect_pending_validation()

    snooze_duration = NeTEx.poll_interval(attempt)

    assert {:snooze, ^snooze_duration} = run_polling_job(validation, validation_id, attempt)

    assert %{
             data_vis: nil,
             max_error: nil,
             metadata: nil,
             oban_args: %{"state" => "waiting", "type" => "netex"},
             result: nil
           } = validation |> DB.Repo.reload() |> DB.Repo.preload(:metadata)
  end

  test "too many attempts" do
    validation = create_validation(%{"type" => "netex"})

    validation_id = with_running_validation() |> expect_pending_validation()

    assert capture_log([level: :error], fn ->
             assert :ok == run_polling_job(validation, validation_id, 181)

             assert %{
                      data_vis: nil,
                      metadata: %{},
                      oban_args: %{
                        "state" => "error",
                        "type" => "netex",
                        "error_reason" => "enRoute Chouette Valid: Timeout while fetching results"
                      },
                      result: nil,
                      validation_timestamp: date
                    } = validation |> DB.Repo.reload() |> DB.Repo.preload(:metadata)

             assert DateTime.diff(date, DateTime.utc_now()) <= 1
           end) =~ "Timeout while fetching result"
  end

  test "completed" do
    validation = create_validation(%{"type" => "netex"})

    validation_id = with_running_validation() |> expect_valid_netex()

    assert :ok == run_polling_job(validation, validation_id)

    assert %{
             data_vis: nil,
             max_error: "NoError",
             metadata: %{},
             oban_args: %{"state" => "completed", "type" => "netex"},
             result: %{},
             validation_timestamp: date
           } = validation |> DB.Repo.reload() |> DB.Repo.preload(:metadata)

    assert DateTime.diff(date, DateTime.utc_now()) <= 1
  end

  test "error" do
    validation = create_validation(%{"type" => "netex"})

    errors = [
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
      }
    ]

    validation_id = with_running_validation() |> expect_netex_with_errors(errors)

    assert :ok == run_polling_job(validation, validation_id)

    assert %{
             data_vis: nil,
             max_error: "error",
             metadata: %{},
             oban_args: %{"state" => "completed", "type" => "netex"},
             result: result,
             validation_timestamp: date
           } = validation |> DB.Repo.reload() |> DB.Repo.preload(:metadata)

    assert %{"xsd-1871" => a1, "uic-operating-period" => a2, "valid-day-bits" => a3, "frame-arret-resources" => a4} =
             result

    assert length(a1) == 1
    assert length(a2) == 1
    assert length(a3) == 1
    assert length(a4) == 1

    assert DateTime.diff(date, DateTime.utc_now()) <= 1
  end

  defp create_validation(details) do
    oban_args =
      details
      |> Map.merge(%{"filename" => @filename, "permanent_url" => mk_url(), "state" => "waiting"})

    insert(:multi_validation, oban_args: oban_args)
  end

  defp mk_url, do: "http://localhost:9999/netex-#{Ecto.UUID.generate()}.zip"

  defp expect_valid_netex(validation_id), do: expect_successful_validation(validation_id, 180)

  defp expect_netex_with_errors(validation_id, messages) do
    expect_failed_validation(validation_id, 10)

    expect_get_messages(validation_id, messages)
  end

  defp run_polling_job(%DB.MultiValidation{} = validation, validation_id, attempt \\ 1) do
    payload =
      validation.oban_args
      |> Map.merge(%{"id" => validation.id, "validation_id" => validation_id})

    perform_job(Transport.Jobs.OnDemandNeTExPollerJob, payload, attempt: attempt)
  end
end
