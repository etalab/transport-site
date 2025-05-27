defmodule Transport.Test.Transport.Jobs.DatabaseVacuumJobTest do
  use ExUnit.Case, async: false
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.DatabaseVacuumJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo, sandbox: false)
    Logger.configure(level: :debug)
  end

  test "vacuum full is executed" do
    {_, log} =
      ExUnit.CaptureLog.with_log(fn ->
        assert :ok == perform_job(DatabaseVacuumJob, %{})
      end)

    assert log =~ "VACUUM FULL"
  end
end
