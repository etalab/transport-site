defmodule Transport.Jobs.ResourceValidationJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import ExUnit.CaptureLog
  import DB.Factory
  import Mox

  setup :verify_on_exit!

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  describe "perform" do
    test "all validations for one resource" do
      %{id: resource_id} = resource = insert(:resource, format: "gtfs-rt")

      Transport.ValidatorsSelection.Mock
      |> expect(:validators, 1, fn ^resource ->
        [Transport.Validators.Dummy]
      end)

      perform_job(Transport.Jobs.ResourceValidationJob, %{"resource_id" => resource_id})

      assert_received :validate!
    end
  end

  test "detects when a resource is not real time" do
    %{id: resource_id} = insert(:resource, format: "csv")

    assert capture_log(fn ->
             assert {:error, "Resource##{resource_id} is not real time"} ==
                      perform_job(Transport.Jobs.ResourceValidationJob, %{"resource_id" => resource_id})
           end) =~ "[warning] Job  handled by Transport.Jobs.ResourceValidationJob"
  end
end
