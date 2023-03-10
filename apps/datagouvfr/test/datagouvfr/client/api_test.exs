defmodule Datagouvfr.Client.APITest do
  use ExUnit.Case, async: true

  doctest Datagouvfr.Client.API, import: true

  import Datagouvfr.ApiFixtures
  import Mox

  alias Datagouvfr.Client.API

  setup :verify_on_exit!

  @data_containing_1_element ["data_containing_1_element #1"]
  @data_containing_2_elements ["data_containing_2_elements #1", "data_containing_2_elements #2"]

  describe "Stream a data.gouv.fr resource" do
    test "when resource is NOT paginated" do
      resource_to_stream = "resource"

      resource_to_stream
      |> API.process_url()
      |> given_request_return_only_one_page(@data_containing_1_element)

      assert_stream_return_pages(resource_to_stream, [{:ok, @data_containing_1_element}])
    end

    test "when resource is paginated" do
      resource_to_stream = "resource"

      resource_to_stream
      |> API.process_url()
      |> given_request_return_response_with_next_page(@data_containing_2_elements)
      |> given_request_return_response_with_next_page(@data_containing_1_element)
      |> given_request_return_response_without_next_page(@data_containing_2_elements)

      assert_stream_return_pages(resource_to_stream, [
        {:ok, @data_containing_2_elements},
        {:ok, @data_containing_1_element},
        {:ok, @data_containing_2_elements}
      ])
    end

    test "when resource's page return an error" do
      resource_to_stream = "resource"

      resource_to_stream
      |> API.process_url()
      |> given_request_return_response_with_next_page(@data_containing_2_elements)
      |> given_request_return_an_error("error page")

      assert_stream_return_pages(
        resource_to_stream,
        [
          {:ok, @data_containing_2_elements},
          {:error, "error page"}
        ]
      )
    end
  end

  test "handles a 308 redirection" do
    path = "foo"
    url = "https://demo.data.gouv.fr/api/1/#{path}/"
    location_url = "https://example/bar"

    # A 308 response and then a 200 response
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 308, headers: [{"location", location_url}], request_url: url}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^location_url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}}
    end)

    assert {:ok, %{}} == API.get(path)
  end

  test "handles a relative 308 redirection" do
    path = "foo"
    url = "https://demo.data.gouv.fr/api/1/#{path}/"
    location_url = "/bar"

    # A 308 response and then a 200 response
    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 308, headers: [{"location", location_url}], request_url: url}}
    end)

    Transport.HTTPoison.Mock
    |> expect(:request, fn :get, "https://demo.data.gouv.fr" <> ^location_url, "", [], [follow_redirect: true] ->
      {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}}
    end)

    assert {:ok, %{}} == API.get(path)
  end

  describe "retry mechanism on timeout" do
    test "retries when there is a timeout" do
      path = "foo"
      url = "https://demo.data.gouv.fr/api/1/#{path}/"

      # A timeout response and then a 200 response
      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      Transport.HTTPoison.Mock
      |> expect(:request, fn :get, ^url, "", [], [follow_redirect: true] ->
        {:ok, %HTTPoison.Response{status_code: 200, body: "{}"}}
      end)

      assert {:ok, %{}} == API.get(path)
    end

    test "retries request up to 3 times and then gives up" do
      path = "foo"
      url = "https://demo.data.gouv.fr/api/1/#{path}/"

      Transport.HTTPoison.Mock
      |> expect(:request, 3, fn :get, ^url, "", [], [follow_redirect: true] ->
        {:error, %HTTPoison.Error{reason: :timeout}}
      end)

      assert {:error, %HTTPoison.Error{reason: :timeout}} == API.get(path)
    end
  end

  defp assert_stream_return_pages(resource_to_stream, expected_pages_data) do
    obtained_pages_data =
      resource_to_stream
      |> API.stream()
      |> Stream.map(fn {response_status, %{"data" => data}} -> {response_status, data} end)
      |> Enum.to_list()

    assert obtained_pages_data == expected_pages_data
  end
end
