defmodule Transport.Test.Transport.Jobs.TableSizeHistoryJobTest do
  use ExUnit.Case, async: true
  use Oban.Testing, repo: DB.Repo
  alias Transport.Jobs.TableSizeHistoryJob

  setup do
    Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "perform" do
    today = Date.utc_today()

    assert :ok == perform_job(TableSizeHistoryJob, %{})

    records = DB.Repo.all(DB.TableSizeHistory)

    assert Enum.count(records) >= 50
    assert Enum.member?(Enum.map(records, & &1.table_name), "dataset")
    assert Enum.uniq(Enum.map(records, & &1.date)) == [today]
  end
end
