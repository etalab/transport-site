defmodule Datagouvfr.Client.CommunityResources.APITest do
  use ExUnit.Case, async: true
  doctest Datagouvfr.Client.CommunityResources.API

  import Datagouvfr.ApiFixtures
  import Mox

  alias Datagouvfr.Client.CommunityResources.API

  setup :verify_on_exit!

  describe "Fetch community resources by dataset id" do
    test "when resource is NOT paginated" do
      a_dataset_id = "a_dataset_id"

      a_dataset_id
      |> build_expected_community_resource_base_url()
      |> expect_request_called_with_only_one_page("page 1 data")

      assert_stream_return_data(a_dataset_id, ["page 1 data"])
    end

    test "when resource is paginated" do
      a_dataset_id = "a_dataset_id"

      a_dataset_id
      |> build_expected_community_resource_base_url()
      |> expect_request_called_and_return_next_page("page 1 data")
      |> expect_request_called_with_only_one_page("page 2 data")

      assert_stream_return_data(a_dataset_id, ["page 1 data", "page 2 data"])
    end

    test "when resource return a page in error" do
      a_dataset_id = "a_dataset_id"

      a_dataset_id
      |> build_expected_community_resource_base_url()
      |> expect_request_called_and_return_next_page("page 1 data")
      |> expect_request_called_and_return_next_page("page 2 data")
      |> expect_request_called_and_return_an_error("community resource error")

      assert_stream_return_an_error(a_dataset_id)
    end
  end

  defp assert_stream_return_data(resource_to_stream, expected_pages_data) do
    obtained_pages_data =
      resource_to_stream
      |> API.get()
      |> Enum.to_list()

    assert obtained_pages_data == expected_pages_data
  end

  defp assert_stream_return_an_error(resource_to_stream) do
    result = resource_to_stream |> API.get()
    assert result == {:error, []}
  end

  defp build_expected_community_resource_base_url(community_resource_id),
    do:
      "/datasets/community_resources?dataset=#{community_resource_id}"
      |> process_url()
end
