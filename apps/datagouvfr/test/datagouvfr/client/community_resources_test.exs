defmodule Datagouvfr.Client.CommunityResources.APITest do
  use ExUnit.Case, async: true
  doctest Datagouvfr.Client.CommunityResources.API

  import Datagouvfr.ApiFixtures
  import Mox

  alias Datagouvfr.Client.CommunityResources.API, as: CommunityResourcesAPI

  setup :verify_on_exit!

  @data_containing_1_element ["data_containing_1_element #1"]
  @data_containing_2_elements ["data_containing_2_elements #1", "data_containing_2_elements #2"]

  describe "Fetch community resources by dataset id" do
    test "when resource is NOT paginated" do
      a_dataset_id = "a_dataset_id"

      a_dataset_id
      |> build_expected_community_resource_base_url()
      |> given_request_return_only_one_page(@data_containing_2_elements)

      a_dataset_id
      |> CommunityResourcesAPI.get()
      |> assert_response_is_valid_and_contains_data(@data_containing_2_elements)
    end

    test "when resource is paginated" do
      a_dataset_id = "a_dataset_id"

      a_dataset_id
      |> build_expected_community_resource_base_url()
      |> given_request_return_response_with_next_page(@data_containing_2_elements)
      |> given_request_return_response_without_next_page(@data_containing_1_element)

      a_dataset_id
      |> CommunityResourcesAPI.get()
      |> assert_response_is_valid_and_contains_data(@data_containing_2_elements ++ @data_containing_1_element)
    end

    test "when resource return a page in error" do
      a_dataset_id = "a_dataset_id"

      a_dataset_id
      |> build_expected_community_resource_base_url()
      |> given_request_return_response_with_next_page(@data_containing_2_elements)
      |> given_request_return_response_with_next_page(@data_containing_1_element)
      |> given_request_return_an_error("community resource error")

      a_dataset_id
      |> CommunityResourcesAPI.get()
      |> assert_is_an_error_response
    end
  end

  defp assert_response_is_valid_and_contains_data({:ok, obtained_data}, expected_data),
    do: assert(obtained_data == expected_data)

  defp assert_is_an_error_response({:error, obtained_data}),
    do: assert(obtained_data == [])

  defp build_expected_community_resource_base_url(community_resource_id),
    do:
      "/datasets/community_resources?dataset=#{community_resource_id}"
      |> process_url()
end
