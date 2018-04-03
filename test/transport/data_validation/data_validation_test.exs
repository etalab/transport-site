defmodule Transport.DataValidationTest do
  use ExUnit.Case, async: true
  use TransportWeb.ExternalCase
  alias Transport.DataValidation

  @moduletag :integration
  doctest DataValidation

  setup do
    {:ok, [
      project_name: Faker.Industry.sector,
      feed_source_name: Faker.Company.name,
      feed_source_url: "https://data.agglo-royan.fr/dataset/9b761974-a195-4e33-91b7-ecee3b368016/resource/144c2734-9d66-4177-904d-a67768f5ee1d/download/carabus-royan-au-23102017.zip"
    ]}
  end

  test "creates a project", %{project_name: name} do
    assert {:ok, %{name: ^name, id: id}} = DataValidation.create_project(%{name: name})
    refute is_nil(id)
  end

  test "finds a project", %{project_name: name} do
    {:ok, project} = DataValidation.create_project(%{name: name})
    assert {:ok, ^project} = DataValidation.find_project(%{name: name})
  end

  test "creates a feed source", %{project_name: project, feed_source_name: name, feed_source_url: url} do
    {:ok, project} = DataValidation.create_project(%{name: project})
    assert {:ok, %{name: ^name, url: ^url, id: id}} = DataValidation.create_feed_source(%{project: project, name: name, url: url})
    refute is_nil(id)
  end

  test "finds a feed source", %{project_name: project, feed_source_name: name, feed_source_url: url} do
    {:ok, project} = DataValidation.create_project(%{name: project})
    {:ok, feed_source} = DataValidation.create_feed_source(%{project: project, name: name, url: url})
    assert {:ok, ^feed_source} = DataValidation.find_feed_source(%{project: project, name: name})
  end

  test "validates a feed source", %{project_name: project, feed_source_name: name, feed_source_url: url} do
    {:ok, project} = DataValidation.create_project(%{name: project})
    {:ok, feed_source} = DataValidation.create_feed_source(%{project: project, name: name, url: url})
    assert :ok = DataValidation.validate_feed_source(%{project: project, feed_source: feed_source})
  end

  test "lists feed sources", %{project_name: project, feed_source_name: name, feed_source_url: url} do
    {:ok, project} = DataValidation.create_project(%{name: project})
    {:ok, feed_source} = DataValidation.create_feed_source(%{project: project, name: name, url: url})
    assert {:ok, [^feed_source]} = DataValidation.list_feed_sources(%{project: project})
  end

  test "finds a feed version", %{project_name: project, feed_source_name: name, feed_source_url: url} do
    {:ok, project} = DataValidation.create_project(%{name: project})
    {:ok, feed_source} = DataValidation.create_feed_source(%{project: project, name: name, url: url})
    :ok = DataValidation.validate_feed_source(%{project: project, feed_source: feed_source})
    {:ok, [%{latest_version_id: latest_version_id}]} = list_feed_sources(%{project: project})
    refute is_nil(latest_version_id)
  end

  defp list_feed_sources(map) do
    map
    |> DataValidation.list_feed_sources
    |> case do
      {:ok, [%{latest_version_id: nil}]} -> list_feed_sources(map)
      {:ok, feed_sources} -> {:ok, feed_sources}
    end
  end
end
