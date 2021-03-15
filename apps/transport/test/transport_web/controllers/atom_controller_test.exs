defmodule TransportWeb.AtomControllerTest do
  use ExUnit.Case, async: false
  import TransportWeb.AtomController
  # use TransportWeb.DatabaseCase, cleanup: [:datasets]
  import TransportWeb.Factory
  alias Timex.Format.DateTime.Formatter

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "get recent resources for atom feed" do
    insert(:resource,
      latest_url: "url",
      last_update: DateTime.now!("Etc/UTC") |> DateTime.add(-10) |> Formatter.format!("{ISO:Extended}")
    )

    now = DateTime.now!("Etc/UTC") |> Formatter.format!("{ISO:Extended}")
    insert(:resource, latest_url: "url", last_update: now)

    insert(:resource, latest_url: "url")

    insert(:resource,
      latest_url: "url",
      last_update: DateTime.now!("Etc/UTC") |> DateTime.add(-3600) |> Formatter.format!("{ISO:Extended}")
    )

    limit = DateTime.now!("Etc/UTC") |> DateTime.add(-1000)

    resources = get_recent_resources(limit)
    # 2 resources are more recent than the limit, 1 is older, 1 has no last_update filled.
    assert resources |> Enum.count() == 2
    # check the sorting works (more recent resources come first)
    first_resource = Enum.at(resources, 0)
    assert first_resource.last_update == now
  end
end
