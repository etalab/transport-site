defmodule Datagouvfr.ApiFixtures do
  @moduledoc """
  Utility module for mocking Data.Gouv.Fr API.
  """

  alias HTTPoison.Response

  import Mox
  import ExUnit.Assertions

  use Datagouvfr.Client

  @doc """
  Mock Data.Gouv.Fr API request and wrap exepected_data into the mocked response.
  Assert that it's called only one time, that the given expected_url is called.
  """
  def given_request_return_only_one_page(expected_url, expected_data),
    do: given_request_return_response_without_next_page(expected_url, expected_data)

  @doc """
  Mock Data.Gouv.Fr API request and wrap exepected_data into the mocked response.
  Also generate a "next_page" url and return it into the mocked response.
  Assert that it's called only one time, that the given expected_url is called.
  """
  def given_request_return_response_with_next_page(expected_url, expected_data)

  def given_request_return_response_with_next_page(expected_url, expected_data)
      when not is_list(expected_data),
      do: given_request_return_response_with_next_page(expected_url, [expected_data])

  def given_request_return_response_with_next_page(expected_url, expected_data) do
    next_page = expected_url <> "_next"
    mocked_response = build_mocked_response(:ok, expected_data, 200, next_page)
    mock_httpoison_request(expected_url, mocked_response)

    next_page
  end

  @doc """
  Mock Data.Gouv.Fr API request to return an error.
  Assert that it's called only one time, that the given expected_url is called.
  An error response does not contains next_page property.
  """
  def given_request_return_an_error(expected_url, error \\ "error") do
    mocked_response = build_mocked_response(:error, expected_url, error)
    mock_httpoison_request(expected_url, mocked_response)
  end

  @doc """
  Mock Data.Gouv.Fr API request and wrap exepected_data into the mocked response.
  Since the resource only have one page, then the mocked response is set with "next_page" property to nil.
  Assert that it's called only one time, that the given expected_url is called.
  """
  def given_request_return_response_without_next_page(expected_url, expected_data) do
    mocked_response = build_mocked_response(:ok, expected_data, 200, nil)
    mock_httpoison_request(expected_url, mocked_response)
    nil
  end

  def mock_httpoison_request(expected_url, expected_response, expected_options \\ nil) do
    Transport.HTTPoison.Mock
    |> expect(
      :request,
      1,
      fn _method, requested_url, _body, _headers, options ->
        assert expected_url == requested_url

        unless is_nil(expected_options) do
          assert expected_options == options
        end

        expected_response
      end
    )
  end

  defp build_mocked_response(:ok, expected_data, expected_status_code, expected_next_page),
    do: {
      :ok,
      %Response{
        status_code: expected_status_code,
        body:
          Jason.encode!(%{
            next_page: expected_next_page,
            data: expected_data
          })
      }
    }

  defp build_mocked_response(:error, expected_status_code, expected_data),
    do: {
      :ok,
      %Response{
        status_code: expected_status_code,
        body:
          Jason.encode!(%{
            data: expected_data
          })
      }
    }
end
