defmodule Transport.Test.Transport.Jobs.UpdateCounterCacheJobTest do
  @moduledoc """
  This test only tests that the job can run, not the actual logic of the job, see `Transport.CounterCacheTest` for that.
  """
  use ExUnit.Case, async: true
  import DB.Factory
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.UpdateCounterCacheJob

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    # Needs at least one resource and friends in database, else the job will fail.
    insert_up_to_date_resource_and_friends()
    assert :ok == perform_job(UpdateCounterCacheJob, %{})
  end
end
