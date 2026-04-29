defmodule TransportWeb.LiveViewTestHelpers do
  @moduledoc """
  Shared helpers for Phoenix LiveView tests.
  """
  import ExUnit.Assertions
  import Phoenix.LiveViewTest

  @doc """
  Like `assert_patched/2`, but compares query params as a map
  to avoid flaky failures due to non-deterministic parameter ordering in URLs.
  """
  def assert_patched_any_params_order(view, expected_url) do
    # assert_patch/1 waits for a patch to happen and returns the actual URL
    actual_url = assert_patch(view)
    actual_uri = URI.parse(actual_url)
    expected_uri = URI.parse(expected_url)
    assert actual_uri.path == expected_uri.path
    assert URI.decode_query(actual_uri.query) == URI.decode_query(expected_uri.query)
  end
end
