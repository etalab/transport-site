defmodule Transport.DataValidation.Aggregates.ProjectTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Commands.{CreateProject, ValidateFeedVersion}
  alias Transport.DataValidation.Queries.FindProject

  doctest Project

  describe "find a project" do
    test "when the project does not exist it returns nil" do
      use_cassette "data_validation/find_project-ok" do
        project = %Project{}
        query   = %FindProject{name: "aires de covoiturage"}
        assert {:reply, {:ok, nil}, ^project} = Project.handle_call({:find_project, query}, nil, project)
      end
    end

    test "when the project exists it returns it from the API" do
      use_cassette "data_validation/find_project-ok" do
        project = %Project{}
        query   = %FindProject{name: "transport"}
        assert {:reply, {:ok, project}, project} = Project.handle_call({:find_project, query}, nil, project)
        refute is_nil(project.id)
      end
    end

    test "when the project exists and already loaded it returns it from memory" do
      project = %Project{id: "1"}
      query   = %FindProject{name: "transport"}
      assert {:reply, {:ok, ^project}, ^project} = Project.handle_call({:find_project, query}, nil, project)
    end

    test "when the API is not available it returns an error" do
      use_cassette "data_validation/find_project-error" do
        project = %Project{}
        query   = %FindProject{name: "transport"}
        assert {:reply, {:error, "econnrefused"}, ^project} = Project.handle_call({:find_project, query}, nil, project)
      end
    end
  end

  describe "create a project" do
    test "when the project does not exist it creates it" do
      use_cassette "data_validation/create_project-ok" do
        project = %Project{id: nil}
        command = %CreateProject{name: "transport"}
        assert {:reply, {:ok, project}, project} = Project.handle_call({:create_project, command}, nil, project)
        refute is_nil(project.id)
      end
    end

    test "when the project already exists it serves it from memory" do
      project = %Project{id: "1"}
      command = %CreateProject{name: "transport"}
      assert {:reply, {:ok, ^project}, ^project} = Project.handle_call({:create_project, command}, nil, project)
    end

    test "when the API is not available it returns an error" do
      use_cassette "data_validation/create_project-error" do
        project = %Project{}
        command = %CreateProject{name: "transport"}
        assert {:reply, {:error, "econnrefused"}, ^project} = Project.handle_call({:create_project, command}, nil, project)
      end
    end
  end

  describe "validate a feed version" do
    test "when the feed version exists it validates it" do
      project = %Project{id: "1"}
      command = %ValidateFeedVersion{id: "1"}
      assert {:reply, {:ok, ^project}, ^project} = Project.handle_call({:validate_feed_version, command}, nil, project)
    end

    test "when the feed version does not exist it fails" do
      project = %Project{id: "1"}
      command = %ValidateFeedVersion{id: "2"}
      assert {:reply, {:error, _}, ^project} = Project.handle_call({:validate_feed_version, command}, nil, project)
    end
  end
end
