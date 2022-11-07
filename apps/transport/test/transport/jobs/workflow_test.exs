defmodule Transport.Jobs.WorkflowTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  import Transport.Jobs.Workflow
  import Ecto.Adapters.SQL.Sandbox
  import ExUnit.CaptureLog

  doctest Transport.Jobs.Workflow, import: true

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "a simple workflow" do
    parent_process = self()

    jobs = [Transport.Jobs.Dummy.JobA, Transport.Jobs.Dummy.JobB]
    some_id = 1

    spawn(fn ->
      # the workflow is spawned in a different process
      # we give it a name
      Process.register(self(), :workflow_process)

      # we allow the process to use the same db sandbox as the main process
      allow(DB.Repo, parent_process, self())

      # the workflow is launched
      perform_job(Transport.Jobs.Workflow, %{
        "jobs" => jobs,
        "first_job_args" => %{"some_id" => some_id}
      })

      Process.unregister(:workflow_process)
    end)

    # we expect the first job to be enqueued
    assert_enqueued(
      [worker: Transport.Jobs.Dummy.JobA, args: %{"some_id" => some_id}],
      200
    )

    # we drain the queue : jobA is effectively executed
    Oban.drain_queue(queue: :default)

    # after job A is done, we expect job B to be enqueued
    assert_enqueued(
      [worker: Transport.Jobs.Dummy.JobB, args: %{"some_id" => some_id + 1}],
      200
    )
  end

  test "a workflow with custom arguments" do
    parent_process = self()

    jobs = [Transport.Jobs.Dummy.JobA, [Transport.Jobs.Dummy.JobB, %{"forced" => true}, []]]
    some_id = 1

    spawn(fn ->
      Process.register(self(), :workflow_process)
      allow(DB.Repo, parent_process, self())

      perform_job(Transport.Jobs.Workflow, %{
        "jobs" => jobs,
        "first_job_args" => %{"some_id" => some_id}
      })
    end)

    assert_enqueued(
      [worker: Transport.Jobs.Dummy.JobA, args: %{"some_id" => some_id}],
      200
    )

    Oban.drain_queue(queue: :default)

    # after job A is done, we expect job B to be enqueued with custom arguments provided ("forced")
    assert_enqueued(
      [worker: Transport.Jobs.Dummy.JobB, args: %{"some_id" => some_id + 1, "forced" => true}],
      200
    )
  end

  test "a workflow with custom job options" do
    parent_process = self()

    jobs = [
      Transport.Jobs.Dummy.JobA,
      [Elixir.Transport.Jobs.Dummy.JobB, %{}, kw_m(queue: :super_heavy, unique: [period: 1])]
    ]

    some_id = 1

    spawn(fn ->
      Process.register(self(), :workflow_process)
      allow(DB.Repo, parent_process, self())

      perform_job(Transport.Jobs.Workflow, %{
        "jobs" => jobs,
        "first_job_args" => %{"some_id" => some_id}
      })

      Process.unregister(:workflow_process)
    end)

    assert_enqueued(
      [worker: Transport.Jobs.Dummy.JobA, args: %{"some_id" => some_id}],
      200
    )

    Oban.drain_queue(queue: :default)

    # after job A is done, we expect job B to be enqueued with on a custom queue
    # I couldn't find a way to test for uniqueness, as the information seems to be erased when the job is enqueued.
    assert_enqueued(
      [worker: Transport.Jobs.Dummy.JobB, args: %{"some_id" => some_id + 1}, queue: :super_heavy],
      50
    )
  end

  test "a workflow with a failing job" do
    parent_process = self()

    jobs = [
      Transport.Jobs.Dummy.FailingJob,
      Transport.Jobs.Dummy.JobA
    ]

    # this id will make FailingJob fail
    some_id = 1

    spawn(fn ->
      Process.register(self(), :workflow_process)
      allow(DB.Repo, parent_process, self())

      {res, logs} =
        with_log(fn ->
          perform_job(Transport.Jobs.Workflow, %{
            "jobs" => jobs,
            "first_job_args" => %{"some_id" => some_id}
          })
        end)

      assert logs =~ "job fails"
      Process.unregister(:workflow_process)

      send(parent_process, res)
    end)

    assert_enqueued(
      [worker: Transport.Jobs.Dummy.FailingJob, args: %{"some_id" => some_id}],
      200
    )

    Oban.drain_queue(queue: :default, with_recursion: true)

    assert_receive({:error, _}, 200)
  end
end
