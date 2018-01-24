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

  test "find a project", %{query: query} do
    use_cassette "data_validation/aggregates/project/find_project" do
      assert {:noreply, project} = Project.handle_cast({:find_project, query}, %Project{})
      refute is_nil(project.id)
    end
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
  end
end
