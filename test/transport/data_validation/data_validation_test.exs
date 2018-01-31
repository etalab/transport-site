defmodule Transport.DataValidationTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation
  alias Transport.DataValidation.Aggregates.Project

  doctest DataValidation

  test "finds a project" do
    use_cassette "data_validation/find_project" do
      assert {:ok, project} = DataValidation.find_project("transport")
      assert project.name == "transport"
      refute is_nil(project.id)
    end
  end

  test "creates a project" do
    use_cassette "data_validation/create_project" do
      start_supervised({Project, "transport"})
      assert :ok == DataValidation.create_project(%{name: "transport"})
    end
  end
end
