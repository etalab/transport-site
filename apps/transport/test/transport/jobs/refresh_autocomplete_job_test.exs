defmodule Transport.Test.Transport.Jobs.RefreshAutocompleteJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.RefreshAutocompleteJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
    Logger.configure(level: :debug)
  end

  test "refresh view is executed" do
    {_, log} =
      ExUnit.CaptureLog.with_log(fn ->
        assert :ok == perform_job(RefreshAutocompleteJob, %{})
      end)

    assert log =~ "REFRESH MATERIALIZED VIEW autocomplete"
  end
end
