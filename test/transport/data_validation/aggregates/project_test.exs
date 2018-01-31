defmodule Transport.DataValidation.Aggregates.ProjectTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Commands.CreateProject
  alias Transport.DataValidation.Queries.FindProject

  doctest Project

  setup do
    query   = %FindProject{name: "transport"}
    command = %CreateProject{name: "transport"}

    {:ok, query: query, command: command}
  end

  @tag :capture_log
  describe "init" do
    test "when API is not available it fails" do
      {:ok, pid} = start_supervised({Project, "transport"})
      ref        = Process.monitor(pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, :econnrefused}
    end
  end

  test "find a project" do
    assert {:reply, {:ok, project}, project} = Project.handle_call({:find_project}, nil, %Project{id: "1"})
  end

  describe "create a project" do
    test "when the project does not exist it creates it", %{command: command} do
      use_cassette "data_validation/aggregates/project/create_project" do
        assert {:noreply, project} = Project.handle_cast({:create_project, command}, %Project{id: nil})
        refute is_nil(project.id)
      end
    end

    test "when the project already exists it serves it from memory", %{command: command} do
      assert {:noreply, project} = Project.handle_cast({:create_project, command}, %Project{id: "1"})
      assert project.id == "1"
    end

    test "when the API is not available it fails", %{command: command} do
      assert {:stop, :econnrefused, _} = Project.handle_cast({:create_project, command}, %Project{id: nil})
    end
  end

  describe "populate project" do
    test "it calls the API to retrieve the project", %{query: query} do
      use_cassette "data_validation/aggregates/project/populate_project" do
        assert {:noreply, project} = Project.handle_cast({:populate_project, query}, %Project{})
        refute is_nil(project.id)
      end
    end

    test "when the API is not available it fails", %{query: query} do
      assert {:stop, :econnrefused, _} = Project.handle_cast({:populate_project, query}, %Project{})
    end
  end
end
