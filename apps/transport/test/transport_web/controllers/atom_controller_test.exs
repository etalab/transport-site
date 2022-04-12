defmodule TransportWeb.AtomControllerTest do
  use TransportWeb.ConnCase, async: true
  import TransportWeb.AtomController
  # use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import DB.Factory
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

  def days_ago_as_naive_iso_string(days) do
    days
    |> days_ago()
    |> NaiveDateTime.to_iso8601()
  end

  test "get recent resources for atom feed" do
    days = 1000

    # Database currently expects datetime as iso string!
    # With or without timezones, we are not too sure, so we insert both
    insert(:resource, title: "10-days-old", last_update: days_ago_as_iso_string(10))
    insert(:resource, title: "today-old", last_update: days_ago_as_iso_string(0))
    insert(:resource, title: "naive-yesterday-old", last_update: days_ago_as_naive_iso_string(1))
    insert(:resource, title: "no-timestamp-should-not-appear", last_update: nil)
    insert(:resource, title: "too-old-should-not-appear", last_update: days_ago_as_iso_string(days * 2))

    limit = days_ago(days)

    resources = get_recently_updated_resources(limit)
    titles = resources |> Enum.map(& &1.title)

    assert titles == [
             # most recent at the top, despite created after
             "today-old",
             "naive-yesterday-old",
             # not too old to be filtered out
             "10-days-old"
             # very old and no timestamp are excluded
           ]
  end

  test "date format in atom feed", %{conn: conn} do
    %{id: dataset_id} = insert(:dataset)
    last_update_utc = days_ago(5)
    insert(:resource, title: "today-old", last_update: last_update_utc |> to_string(), dataset_id: dataset_id)

    conn = conn |> get(atom_path(conn, :index))

    # The timestamp displayed gets converted from UTC to Paris timezone
    last_update_paris = last_update_utc |> Timex.Timezone.convert("Europe/Paris") |> Formatter.format!("{ISO:Extended}")

    doc = conn |> response(200) |> Floki.parse_document!()
    assert {"updated", [], [last_update_paris]} == doc |> Floki.find("updated") |> Enum.at(0)
  end
end
