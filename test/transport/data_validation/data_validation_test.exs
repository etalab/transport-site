defmodule Transport.DataValidationTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation

  doctest DataValidation

  test "finds a project" do
    use_cassette "data_validation/find_project-ok" do
      assert {:ok, project} = DataValidation.find_project(%{name: "transport"})
      assert project.name == "transport"
      refute is_nil(project.id)
    end
  end

  test "creates a project" do
    use_cassette "data_validation/create_project-ok" do
      assert {:ok, project} = DataValidation.create_project(%{name: "transport"})
      assert project.name == "transport"
      refute is_nil(project.id)
    end
  end

  test "finds a feed source" do
    use_cassette "data_validation/find_feed_source-ok" do
      assert {:ok, project} = DataValidation.find_project(%{name: "transport"})
      assert {:ok, feed_source} = DataValidation.find_feed_source(%{project: project, name: "tisseo"})
      refute is_nil(feed_source.id)
    end
  end

  test "creates a feed source" do
    use_cassette "data_validation/create_feed_source-ok" do
      assert {:ok, project} = DataValidation.find_project(%{name: "transport"})
      assert {:ok, feed_source} = DataValidation.create_feed_source(%{project: project, name: "tisseo"})
      refute is_nil(feed_source.id)
    end
  end
end
