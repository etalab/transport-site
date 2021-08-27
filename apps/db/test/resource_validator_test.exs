defmodule DB.ResourceValidatorTest do
  use ExUnit.Case
  import Mox

  setup :verify_on_exit!

  describe "the transport gtfs validator" do
    test "with a validation going well" do
      resource_url = "url"

      Transport.HTTPoison.Mock
      |> expect(:get, 1, fn url, [], _ ->
        assert url |> String.contains?(resource_url)
        {:ok, %HTTPoison.Response{status_code: 200, body: "{\"is_valid\": true}"}}
      end)

      validation = %DB.Resource{format: "GTFS", url: resource_url} |> DB.Resource.GtfsTransportValidator.validate
      assert {:ok, %{"is_valid" => true}} == validation
    end

    test "with a validation failing" do
      resource_url = "url"

      Transport.HTTPoison.Mock
      |> expect(:get, 1, fn url, [], _ ->
        assert url |> String.contains?(resource_url)
        {:ok, %HTTPoison.Response{status_code: 500, body: "internal server error"}}
      end)

      validation = %DB.Resource{format: "GTFS", url: resource_url} |> DB.Resource.GtfsTransportValidator.validate
      assert {:error, "internal server error"} == validation
    end

    test "with a wrong format" do
      {:error, msg} = %DB.Resource{format: "CSV", url: "url"} |> DB.Resource.GtfsTransportValidator.validate
      assert msg |> String.contains?("can only validate GTFS resources")
    end

    test "with a missing url" do
      {:error, msg} = %DB.Resource{format: "GTFS", url: nil} |> DB.Resource.GtfsTransportValidator.validate
      assert msg == "No Resource url provided"
    end
  end
end
