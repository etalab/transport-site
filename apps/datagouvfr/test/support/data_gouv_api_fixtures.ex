defmodule Datagouvfr.ApiFixtures do
  @moduledoc """
  Utility module for mocking Data.Gouv.Fr API.
  """

  alias Datagouvfr.Client.API
  alias HTTPoison.Response

  import Mox
  import ExUnit.Assertions

  use Datagouvfr.Client

  @doc """
  Mock Data.Gouv.Fr API request and wrap exepected_data into the mocked response.
  Assert that it's called only one time, that the given expected_url is called.
  """
  def expect_request_called_with_only_one_page(expected_url, expected_data),
    do: expect_request_called_without_next_page(expected_url, expected_data)

  @doc """
  Mock Data.Gouv.Fr API request and wrap exepected_data into the mocked response.
  Also generate a "next_page" url and return it into the mocked response.
  Assert that it's called only one time, that the given expected_url is called.
  """
  def expect_request_called_and_return_next_page(expected_url, expected_data, has_next_page? \\ true) do
    next_page =
      case has_next_page? do
        true -> expected_url <> "_next"
        false -> nil
      end

    mocked_response = {
      :ok,
      %Response{
        status_code: 200,
        body:
          Jason.encode!(%{
            next_page: next_page,
            data: expected_data
          })
      }
    }

    mock_httpoison_request(expected_url, mocked_response)

    next_page
  end

  @doc """
  Mock Data.Gouv.Fr API request to return an error.
  Assert that it's called only one time, that the given expected_url is called.
  An error response does not contains next_page property.
  """
  def expect_request_called_and_return_an_error(expected_url, error \\ "error") do
    mocked_response = {
      :ok,
      %Response{
        status_code: 500,
        body:
          Jason.encode!(%{
            data: error
          })
      }
    }

    mock_httpoison_request(expected_url, mocked_response)
  end

  @doc """
  Mock Data.Gouv.Fr API request and wrap exepected_data into the mocked response.
  Since the resource only have one page, then the mocked response is set with "next_page" property to nil.
  Assert that it's called only one time, that the given expected_url is called.
  """
  def expect_request_called_without_next_page(expected_url, expected_data) do
    expect_request_called_and_return_next_page(expected_url, expected_data, false)
    nil
  end

  def mock_httpoison_request(expected_url, expected_response) do
    Transport.HTTPoison.Mock
    |> expect(
      :request,
      1,
      fn _method, requested_url, _body, _headers, _options ->
        assert expected_url == requested_url
        expected_response
      end
    )
  end
end
