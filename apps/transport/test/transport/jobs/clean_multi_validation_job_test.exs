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

  test "perform for real-time resources" do
    now = DateTime.utc_now()
    month_ago = now |> DateTime.add(-30, :day)
    two_month_ago = now |> DateTime.add(-60, :day)
    %DB.Resource{id: r1_id} = r1 = insert(:resource)
    %DB.Resource{id: r2_id} = r2 = insert(:resource)

    insert(:multi_validation, result: %{"value" => 4}, resource: r1, inserted_at: two_month_ago)
    insert(:multi_validation, result: %{"value" => 3}, resource: r1, inserted_at: month_ago)
    insert(:multi_validation, result: %{"value" => 2}, resource: r1, inserted_at: month_ago)
    insert(:multi_validation, result: %{"value" => 1}, resource: r1, inserted_at: now)

    insert(:multi_validation, result: %{"value" => 3}, resource: r2, inserted_at: month_ago)
    insert(:multi_validation, result: %{"value" => 2}, resource: r2, inserted_at: month_ago)
    insert(:multi_validation, result: %{"value" => 1}, resource: r2, inserted_at: now)

    assert :ok == perform_job(CleanMultiValidationJob, %{"real_time" => true})

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
             %Oban.Job{
               worker: "Transport.Jobs.CleanMultiValidationJob",
               state: "scheduled",
               args: %{"real_time" => true}
             }
           ] = all_enqueued()
  end

  test "perform for static resources" do
    %DB.Resource{id: r1_id} = r1 = insert(:resource)
    %DB.Resource{id: r2_id} = r2 = insert(:resource)

    insert(:multi_validation, result: %{"value" => 4}, resource_history: insert(:resource_history, resource: r1))
    insert(:multi_validation, result: %{"value" => 3}, resource_history: insert(:resource_history, resource: r1))
    insert(:multi_validation, result: %{"value" => 2}, resource_history: insert(:resource_history, resource: r1))
    insert(:multi_validation, result: %{"value" => 1}, resource_history: insert(:resource_history, resource: r1))

    insert(:multi_validation, result: %{"value" => 3}, resource_history: insert(:resource_history, resource: r2))
    insert(:multi_validation, result: %{"value" => 2}, resource_history: insert(:resource_history, resource: r2))
    insert(:multi_validation, result: %{"value" => 1}, resource_history: insert(:resource_history, resource: r2))

    assert :ok == perform_job(CleanMultiValidationJob, %{"static" => true})

    # oldest record has been nullified
    assert [
             nil,
             %{"value" => 3},
             %{"value" => 2},
             %{"value" => 1}
           ] == results_for_resource_history(r1_id)

    # records have not been touched
    assert [
             %{"value" => 3},
             %{"value" => 2},
             %{"value" => 1}
           ] == results_for_resource_history(r2_id)

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.CleanMultiValidationJob",
               state: "scheduled",
               args: %{"static" => true}
             }
           ] = all_enqueued()
  end

  test "perform dispatches both jobs" do
    assert :ok == perform_job(CleanMultiValidationJob, %{})

    assert [
             %Oban.Job{
               worker: "Transport.Jobs.CleanMultiValidationJob",
               state: "available",
               args: %{"real_time" => true}
             },
             %Oban.Job{
               worker: "Transport.Jobs.CleanMultiValidationJob",
               state: "available",
               args: %{"static" => true}
             }
           ] = all_enqueued()
  end

  defp results_for_resource_id(r_id) do
    DB.MultiValidation.with_result()
    |> where([mv], mv.resource_id == ^r_id)
    |> order_by([mv], {:asc, mv.id})
    |> DB.Repo.all()
    |> Enum.map(& &1.result)
  end

  def results_for_resource_history(r_id) do
    DB.MultiValidation.with_result()
    |> join(:inner, [mv], rh in DB.ResourceHistory, on: rh.id == mv.resource_history_id)
    |> where([_mv, rh], rh.resource_id == ^r_id)
    |> order_by([mv], {:asc, mv.id})
    |> DB.Repo.all()
    |> Enum.map(& &1.result)
  end
end
