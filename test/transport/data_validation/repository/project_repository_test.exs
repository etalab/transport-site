defmodule Transport.DataValidation.Repository.ProjectRepositoryTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation.Repository.ProjectRepository
  alias Transport.DataValidation.Queries.FindProject

  doctest ProjectRepository

  describe "find a project" do
    test "when the project exists it returns the project" do
      use_cassette "data_validation/find_project-ok" do
        name  = "transport"
        query = %FindProject{name: name}
        assert {:ok, %{name: ^name}} = ProjectRepository.execute(query)
      end
    end

    test "when the project does not exist it returns nil" do
      use_cassette "data_validation/find_project-not_found" do
        query = %FindProject{name: "aires de covoiturage"}
        assert {:ok, nil} = ProjectRepository.execute(query)
      end
    end

    test "when the API is not available it returns an error" do
      use_cassette "data_validation/find_project-error" do
        query = %FindProject{name: "transport"}
        assert {:error, "econnrefused"} = ProjectRepository.execute(query)
      end
    end
  end
end
