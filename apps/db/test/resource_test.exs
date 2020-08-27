defmodule Transport.ResourceTest do
  use ExUnit.Case, async: true
  alias DB.{Resource, Validation}

  doctest Resource

  test "validate empty resource" do
    resource = %Resource{}
    assert {:error, _} = Resource.validate(resource, Resource.Validator.Mock)
  end

  test "validate non GTFS resource" do
    resource = %Resource{url: "myurl", format: "NeTEx"}
    assert {:ok, %{"validations" => nil, "metadata" => nil}} = Resource.validate(resource, Resource.Validator.Mock)
  end

  test "validate GTFS resource with 200 response" do
    resource = %Resource{url: "200_url", format: "GTFS"}
    assert {:ok, %{"details" => _}} = Resource.validate(resource, Resource.Validator.Mock)
  end

  test "validate GTFS resource with 404 response" do
    resource = %Resource{url: "404_url", format: "GTFS"}
    assert {:error, _} = Resource.validate(resource, Resource.Validator.Mock)
  end

  test "has resource metadata ? (false)" do
    resource = %Resource{}
    assert not Resource.has_metadata?(resource)
  end

  test "has resource metadata ? (false again)" do
    resource = %Resource{metadata: nil}
    assert not Resource.has_metadata?(resource)
  end

  test "has resource metadata ? (true)" do
    resource = %Resource{metadata: "some metadatas"}
    assert Resource.has_metadata?(resource)
  end
end
