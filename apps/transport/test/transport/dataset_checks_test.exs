defmodule Transport.DatasetChecksTest do
  use ExUnit.Case, async: true
  import DB.Factory

  setup do
    Mox.stub_with(Transport.ValidatorsSelection.Mock, Transport.ValidatorsSelection.Impl)
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "check" do
    dataset = insert(:dataset)
    %DB.Resource{id: r1_id} = insert(:resource, dataset: dataset, is_available: false)
    insert(:resource, dataset: dataset, is_available: true)

    %{resource: %{id: r3_id}, multi_validation: %{id: mv1_id}} =
      insert_resource_and_friends(Date.utc_today(), dataset: dataset)

    %{resource: %{id: r4_id}, multi_validation: %{id: mv2_id}} =
      insert_resource_and_friends(Date.add(Date.utc_today(), 10), dataset: dataset, max_error: "Error")

    assert %{
             unavailable_resource: [%DB.Resource{id: ^r1_id, is_available: false}],
             expiring_resource: [{%DB.Resource{id: ^r3_id}, [%DB.MultiValidation{id: ^mv1_id}]}],
             invalid_resource: [
               {%DB.Resource{id: ^r4_id},
                [%DB.MultiValidation{id: ^mv2_id, digest: %{"max_severity" => %{"max_level" => "Error"}}}]}
             ]
           } = Transport.DatasetChecks.check(dataset)
  end

  test "has_issues?" do
    d1 = insert(:dataset)
    d2 = insert(:dataset)
    insert(:resource, dataset: d2, is_available: false)

    refute Transport.DatasetChecks.check(d1) |> Transport.DatasetChecks.has_issues?()
    assert Transport.DatasetChecks.check(d2) |> Transport.DatasetChecks.has_issues?()
  end
end
