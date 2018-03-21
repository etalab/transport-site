defmodule Transport.DataValidation.Repository.ProjectRepositoryTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation.Repository.ProjectRepository
  alias Transport.DataValidation.Queries.FindProject
  alias Transport.DataValidation.Commands.CreateProject

  doctest ProjectRepository

  describe "find a project" do
    test "when the project exists it returns the project" do
      use_cassette "data_validation/find_project-ok" do
        name   = "transport"
        action = %FindProject{name: name}
        assert {:ok, %{name: ^name}} = ProjectRepository.execute(action)
      end
    end

    test "when the project does not exist it returns nil" do
      use_cassette "data_validation/find_project-not_found" do
        action = %FindProject{name: "aires de covoiturage"}
        assert {:ok, nil} = ProjectRepository.execute(action)
      end
    end

    test "when the API is not available it returns an error" do
      use_cassette "data_validation/find_project-error" do
        action = %FindProject{name: "transport"}
        assert {:error, "econnrefused"} = ProjectRepository.execute(action)
      end
    end
  end

  describe "create a project" do
    test "when the API is available it creates a project" do
      use_cassette "data_validation/create_project-ok" do
        name   = "transport"
        action = %CreateProject{name: name}
        assert {:ok, %{name: ^name}} = ProjectRepository.execute(action)
      end
    end

    test "when the API is not available it returns an error" do
      use_cassette "data_validation/create_project-error" do
        action = %CreateProject{name: "transport"}
        assert {:error, "econnrefused"} = ProjectRepository.execute(action)
      end
    end
  end
end
