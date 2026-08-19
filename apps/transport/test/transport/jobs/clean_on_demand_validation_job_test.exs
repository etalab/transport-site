defmodule Transport.Test.Transport.Jobs.CleanOnDemandValidationJobTest do
  use ExUnit.Case, async: true
  import DB.Factory
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
    two_month_ago = today |> DateTime.add(-60, :day)
    three_months_ago = today |> DateTime.add(-90, :day)

    insert_on_demand_validation(inserted_at: last_week)
    insert_on_demand_validation(inserted_at: last_month)
    insert_on_demand_validation(inserted_at: last_month)
    insert_on_demand_validation(inserted_at: three_months_ago)

    # inserted more than 30 days ago, but already cleaned => should not be included
    insert_on_demand_validation(result: nil, binary_result: nil, inserted_at: two_month_ago)

    assert :ok == perform_job(CleanOnDemandValidationJob, %{})

    last_month_date = last_month |> to_iso_date()
    three_months_ago_date = three_months_ago |> to_iso_date()

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

  # NeTEx validations only fill `binary_result`, `result` stays nil
  test "enqueues jobs for rows having only a binary_result" do
    three_months_ago = DateTime.utc_now() |> DateTime.add(-90, :day)

    insert_on_demand_validation(result: nil, inserted_at: three_months_ago)

    assert :ok == perform_job(CleanOnDemandValidationJob, %{})

    three_months_ago_date = three_months_ago |> to_iso_date()

    assert [%Oban.Job{state: "scheduled", args: %{"date" => ^three_months_ago_date}}] = all_enqueued()
  end

  test "archives rows for a given day" do
    test_datetime = DateTime.utc_now() |> DateTime.add(-31, :day)
    other_datetime = test_datetime |> DateTime.add(-1, :day)

    %{id: mv_id} = insert_on_demand_validation(inserted_at: test_datetime)

    # multi_validation created on another day: should be left untouched
    %{id: mv2_id} = insert_on_demand_validation(inserted_at: other_datetime)

    # multi_validation with `oban_args = nil`: should be left untouched
    %{id: mv3_id} = insert_on_demand_validation(oban_args: nil, inserted_at: test_datetime)

    assert :ok == archive_day(test_datetime)

    # `result`, `binary_result` and `data_vis` have been cleaned
    assert %DB.MultiValidation{result: nil, binary_result: nil, data_vis: nil} = load_multivalidation(mv_id)

    # Other records have not changed
    assert %DB.MultiValidation{result: %{"result" => 42}, binary_result: <<42>>, data_vis: %{"data_vis" => 42}} =
             load_multivalidation(mv2_id)

    assert %DB.MultiValidation{result: %{"result" => 42}, binary_result: <<42>>, data_vis: %{"data_vis" => 42}} =
             load_multivalidation(mv3_id)
  end

  test "archives rows having only a binary_result" do
    test_datetime = DateTime.utc_now() |> DateTime.add(-31, :day)

    %{id: mv_id} = insert_on_demand_validation(result: nil, inserted_at: test_datetime)

    # Without this, the assertion below would also hold for a row we failed to load
    assert %DB.MultiValidation{binary_result: <<42>>} = load_multivalidation(mv_id)

    assert :ok == archive_day(test_datetime)

    assert %DB.MultiValidation{binary_result: nil, data_vis: nil} = load_multivalidation(mv_id)
  end

  test "does not try to archive if not past the retention period" do
    assert {:cancel, "Cannot archive rows if they are not older than 30 days"} =
             perform_job(CleanOnDemandValidationJob, %{"date" => Date.utc_today() |> Date.to_iso8601()})
  end

  # An on-demand validation is attached to neither a resource nor a resource history
  defp insert_on_demand_validation(attrs) do
    defaults = [
      oban_args: %{"foo" => "bar"},
      result: %{"result" => 42},
      binary_result: <<42>>,
      data_vis: %{"data_vis" => 42}
    ]

    insert(:multi_validation, Keyword.merge(defaults, attrs))
  end

  defp archive_day(datetime) do
    perform_job(CleanOnDemandValidationJob, %{"date" => to_iso_date(datetime)})
  end

  defp to_iso_date(datetime), do: datetime |> DateTime.to_date() |> Date.to_iso8601()

  defp load_multivalidation(mv_id) do
    DB.MultiValidation.base_query(include_result: true, include_binary_result: true)
    |> DB.Repo.get!(mv_id)
  end
end
