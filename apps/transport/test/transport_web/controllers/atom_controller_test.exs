defmodule TransportWeb.AtomControllerTest do
  use ExUnit.Case, async: true
  import TransportWeb.AtomController
  # use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import TransportWeb.Factory
  alias Timex.Format.DateTime.Formatter

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  def days_ago(days) do
    "Etc/UTC"
    |> DateTime.now!()
    |> DateTime.add(-days * 24 * 3600)
  end

  def days_ago_as_iso_string(days) do
    days
    |> days_ago()
    |> Formatter.format!("{ISO:Extended}")
  end

  test "get recent resources for atom feed" do
    days = 1000

    # Database currently expects datetime as iso string!
    insert(:resource, title: "10-days-old", last_update: days_ago_as_iso_string(div(days, 2)))
    insert(:resource, title: "today-old", last_update: now = days_ago_as_iso_string(0))
    insert(:resource, title: "no-timestamp-should-not-appear", last_update: nil)
    insert(:resource, title: "too-old-should-not-appear", last_update: days_ago_as_iso_string(days * 2))

    limit = days_ago(days)

    resources = get_recently_updated_resources(limit)
    titles = resources |> Enum.map(& &1.title)

    assert titles == [
             # most recent at the top, despite created after
             "today-old",
             # not too old to be filtered out
             "10-days-old"
             # very old and no timestamp are excluded
           ]
  end
end
