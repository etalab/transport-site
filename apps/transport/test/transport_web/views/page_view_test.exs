defmodule TransportWeb.PageViewTest do
  use ExUnit.Case, async: true
  import DB.Factory
  doctest TransportWeb.PageView, import: true

  setup do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(DB.Repo)
  end

  test "show_downloads_stats?" do
    dataset = insert(:dataset)
    refute dataset |> DB.Repo.preload(:resources) |> TransportWeb.PageView.show_downloads_stats?()

    resource = insert(:resource, dataset: dataset)
    refute DB.Resource.hosted_on_datagouv?(resource)
    refute dataset |> DB.Repo.preload(:resources) |> TransportWeb.PageView.show_downloads_stats?()

    resource = insert(:resource, dataset: dataset, url: "https://static.data.gouv.fr/file.csv")
    assert DB.Resource.hosted_on_datagouv?(resource)
    assert dataset |> DB.Repo.preload(:resources) |> TransportWeb.PageView.show_downloads_stats?()

    # Works with list
    dataset = dataset |> DB.Repo.preload(:resources)
    other_dataset = insert(:dataset) |> DB.Repo.preload(:resources)
    assert [dataset, other_dataset] |> TransportWeb.PageView.show_downloads_stats?()
  end
end
