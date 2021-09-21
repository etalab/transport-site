defmodule Datagouvfr.Client.APITest do
  use ExUnit.Case, async: true

  doctest Datagouvfr.Client.API

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
      |> expect_request_called_with_only_one_page(@data_containing_1_element)

      assert_stream_return_pages(resource_to_stream, [{:ok, @data_containing_1_element}])
    end

    test "when resource is paginated" do
      resource_to_stream = "resource"

      resource_to_stream
      |> API.process_url()
      |> expect_request_called_and_return_next_page(@data_containing_2_elements)
      |> expect_request_called_and_return_next_page(@data_containing_1_element)
      |> expect_request_called_without_next_page(@data_containing_2_elements)

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
      |> expect_request_called_and_return_next_page(@data_containing_2_elements)
      |> expect_request_called_and_return_an_error("error page")

      assert_stream_return_pages(
        resource_to_stream,
        [
          {:ok, @data_containing_2_elements},
          {:error, "error page"}
        ]
      )
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
