defmodule Transport.DataValidationTest do
  use ExUnit.Case, async: false
  use TransportWeb.ExternalCase
  alias Transport.DataValidation

  doctest DataValidation

  test "creates a project" do
    use_cassette "data_validation/create_project" do
      assert :ok == DataValidation.create_project(%{name: "transport"})
    end
  end
end
