defmodule Transport.DataValidation.Aggregates.ProjectTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation.Aggregates.{Project, FeedSource}
  alias Transport.DataValidation.Queries.{FindProject, FindFeedSource}
  alias Transport.DataValidation.Commands.{CreateProject, CreateFeedSource}

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

    test "when the project exists and is already loaded it returns it from memory" do
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

  describe "find a feed source" do
    test "when the feed source does not exist it returns nil" do
      use_cassette "data_validation/find_feed_source-ok" do
        project = %Project{id: "1"}
        query   = %FindFeedSource{project: project, name: "angers"}
        assert {:reply, {:ok, nil}, ^project} = Project.handle_call({:find_feed_source, query}, nil, project)
      end
    end

    test "when the feed source exists it returns it from the API" do
      use_cassette "data_validation/find_feed_source-ok" do
        project = %Project{id: "1"}
        query   = %FindFeedSource{project: project, name: "tisseo"}
        assert {:reply, {:ok, feed_source}, project} = Project.handle_call({:find_feed_source, query}, nil, project)
        assert %{feed_sources: [^feed_source]} = project
      end
    end

    test "when the feed source exists and is already loaded it returns it from memory" do
      feed_source = %FeedSource{id: "1", name: "tisseo"}
      project     = %Project{id: "1", feed_sources: [feed_source]}
      query       = %FindFeedSource{project: project, name: "tisseo"}
      assert {:reply, {:ok, ^feed_source}, ^project} = Project.handle_call({:find_feed_source, query}, nil, project)
    end

    test "when the API is not available it returns an error" do
      use_cassette "data_validation/find_feed_source-error" do
        project = %Project{id: "1", feed_sources: []}
        query   = %FindFeedSource{project: project, name: "tisseo"}
        assert {:reply, {:error, "econnrefused"}, ^project} = Project.handle_call({:find_feed_source, query}, nil, project)
      end
    end
  end

  describe "create a feed source" do
    test "when the feed source does not exist it creates it" do
      use_cassette "data_validation/create_feed_source-ok" do
        project = %Project{id: "1"}
        command = %CreateFeedSource{project: project, name: "tisseo", url: "gtfs.zip"}
        assert {:reply, {:ok, feed_source}, project} = Project.handle_call({:create_feed_source, command}, nil, project)
        assert %{feed_sources: [^feed_source]} = project
      end
    end

    test "when the feed source already exists it serves it from memory" do
      feed_source = %FeedSource{id: "1", name: "tisseo", url: "gtfs.zip"}
      project     = %Project{id: "1", feed_sources: [feed_source]}
      command     = %CreateFeedSource{project: project, name: "tisseo"}
      assert {:reply, {:ok, ^feed_source}, ^project} = Project.handle_call({:create_feed_source, command}, nil, project)
    end

    test "when the API is not available it returns an error" do
      use_cassette "data_validation/create_feed_source-error" do
        project = %Project{id: "1"}
        command = %CreateFeedSource{project: project, name: "tisseo", url: "gtfs.zip"}
        assert {:reply, {:error, "econnrefused"}, ^project} = Project.handle_call({:create_feed_source, command}, nil, project)
      end
    end
  end
end
