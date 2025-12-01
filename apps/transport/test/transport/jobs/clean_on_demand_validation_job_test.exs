defmodule Transport.Test.Transport.Jobs.CleanOnDemandValidationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
  import Ecto.Query
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.CleanOnDemandValidationJob

  doctest CleanOnDemandValidationJob, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "enqueues jobs" do
    today = DateTime.utc_now()
    last_week = today |> DateTime.add(-7, :day)
    last_month = today |> DateTime.add(-30, :day)
    two_month_ago = today |> DateTime.add(-30, :day)
    three_months_ago = today |> DateTime.add(-90, :day)

    insert(:multi_validation, result: %{"valid" => true}, oban_args: %{"foo" => "bar"}, inserted_at: last_week)
    insert(:multi_validation, result: %{"valid" => true}, oban_args: %{"foo" => "bar"}, inserted_at: last_month)
    insert(:multi_validation, result: %{"valid" => true}, oban_args: %{"foo" => "bar"}, inserted_at: last_month)
    insert(:multi_validation, result: %{"valid" => true}, oban_args: %{"foo" => "bar"}, inserted_at: three_months_ago)

    # inserted more than 30 days ago, but already cleaned => should not be included
    insert(:multi_validation, result: nil, oban_args: %{"foo" => "bar"}, inserted_at: two_month_ago)

    assert :ok == perform_job(CleanOnDemandValidationJob, %{})

    last_month_date = last_month |> DateTime.to_date() |> Date.to_iso8601()
    three_months_ago_date = three_months_ago |> DateTime.to_date() |> Date.to_iso8601()

    assert [
             %Oban.Job{
               state: "scheduled",
               worker: "Transport.Jobs.CleanOnDemandValidationJob",
               args: %{"date" => ^last_month_date}
             },
             %Oban.Job{
               state: "scheduled",
               worker: "Transport.Jobs.CleanOnDemandValidationJob",
               args: %{"date" => ^three_months_ago_date}
             }
           ] = all_enqueued()
  end

  test "archives rows for a given day" do
    test_datetime = DateTime.utc_now() |> DateTime.add(-31, :day)
    other_datetime = test_datetime |> DateTime.add(-1, :day)

    mv =
      insert(:multi_validation,
        oban_args: %{"foo" => "bar"},
        result: %{"result" => 42},
        data_vis: %{"data_vis" => 42},
        inserted_at: test_datetime
      )

    # multi_validation created on another day: should be left untouched
    %{id: mv2_id} =
      insert(:multi_validation,
        oban_args: %{"foo" => "bar"},
        result: %{"result" => 42},
        data_vis: %{"data_vis" => 42},
        inserted_at: other_datetime
      )

    # multi_validation with `oban_args = nil`: should be left untouched
    %{id: mv3_id} =
      insert(:multi_validation,
        oban_args: nil,
        result: %{"result" => 42},
        data_vis: %{"data_vis" => 42},
        inserted_at: test_datetime
      )

    assert :ok ==
             perform_job(CleanOnDemandValidationJob, %{
               "date" => test_datetime |> DateTime.to_date() |> Date.to_iso8601()
             })

    # `result` and `data_vis` have been cleaned
    %DB.MultiValidation{result: nil, data_vis: nil} = DB.Repo.reload(mv)

    # Other records have not changed
    %DB.MultiValidation{result: %{"result" => 42}, data_vis: %{"data_vis" => 42}} =
      DB.MultiValidation.with_result() |> where([mv], mv.id == ^mv2_id) |> DB.Repo.one!()

    %DB.MultiValidation{result: %{"result" => 42}, data_vis: %{"data_vis" => 42}} =
      DB.MultiValidation.with_result() |> where([mv], mv.id == ^mv3_id) |> DB.Repo.one!()
  end

  test "does not try to archive if not past the retention period" do
    assert {:cancel, "Cannot archive rows if they are not older than 30 days"} =
             perform_job(CleanOnDemandValidationJob, %{"date" => Date.utc_today() |> Date.to_iso8601()})
  end
end
