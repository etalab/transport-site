defmodule Transport.DataValidation.Aggregates.ProjectTest do
  use ExUnit.Case, async: true
  use TransportWeb.ExternalCase
  alias Transport.DataValidation.Aggregates.Project
  alias Transport.DataValidation.Commands.CreateProject

  doctest Project

  setup do
    command = %CreateProject{name: "transport"}
    project = %Project{id: nil}
    {:ok, command: command, project: project}
  end

  describe "create a project" do
    test "when the project does not exist it creates it", %{command: command, project: project} do
      use_cassette "data_validation/create_project/does-not-exist" do
        assert {:noreply, project} = Project.handle_cast({:create_project, command}, project)
        refute is_nil(project.id)
      end
    end

    test "when the project already exists it serves it from memory", %{command: command, project: project} do
      assert {:noreply, project} = Project.handle_cast({:create_project, command}, %Project{project | id: "1"})
      assert project.id == "1"
    end
  end
end
