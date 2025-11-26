defmodule Transport.Test.Transport.Jobs.CleanMultiValidationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.CleanMultiValidationJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "max_records is set to 1 in test" do
    assert CleanMultiValidationJob.max_records() == 1
  end

  test "perform" do
    %DB.Resource{id: r1_id} = r1 = insert(:resource)
    %DB.Resource{id: r2_id} = r2 = insert(:resource)

    insert(:multi_validation, result: %{"value" => 4}, resource: r1)
    insert(:multi_validation, result: %{"value" => 3}, resource: r1)
    insert(:multi_validation, result: %{"value" => 2}, resource: r1)
    insert(:multi_validation, result: %{"value" => 1}, resource: r1)

    insert(:multi_validation, result: %{"value" => 3}, resource: r2)
    insert(:multi_validation, result: %{"value" => 2}, resource: r2)
    insert(:multi_validation, result: %{"value" => 1}, resource: r2)

    assert :ok == perform_job(CleanMultiValidationJob, %{})

    # oldest record has been nullified
    assert [
             nil,
             %{"value" => 3},
             %{"value" => 2},
             %{"value" => 1}
           ] == results_for_resource_id(r1_id)

    # records have not been touched
    assert [
             %{"value" => 3},
             %{"value" => 2},
             %{"value" => 1}
           ] == results_for_resource_id(r2_id)

    assert [
             %Oban.Job{worker: "Transport.Jobs.CleanMultiValidationJob", state: "scheduled"}
           ] = all_enqueued()
  end

  defp results_for_resource_id(r_id) do
    DB.MultiValidation.with_result()
    |> where([mv], mv.resource_id == ^r_id)
    |> order_by([mv], {:asc, mv.id})
    |> DB.Repo.all()
    |> Enum.map(& &1.result)
  end
end
