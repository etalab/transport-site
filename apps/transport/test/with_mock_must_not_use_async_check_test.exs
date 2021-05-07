defmodule WithMockMustNotUseAsyncCheckTest do
  @moduledoc """
  A very cheap and not super reliable way to ensure a developer
  using "with_mock" together with "async: true" will be warned
  that this should not be used, because it will cause troubles.
  """
  use ExUnit.Case

  test "async must be set to false if you use with_mock" do
    files =
      Path.wildcard("../../apps/**/*_test.exs")
      |> Enum.filter(&potential_incorrect_use_detected?/1)
      |> Enum.map(&Path.relative_to(&1, "../.."))

    assert files == []
  end

  def potential_incorrect_use_detected?(file) do
    content = File.read!(file)
    is_async = String.contains?(content, "async: true")
    use_mock = String.match?(content, ~r/with_mocks? /)
    use_mock && is_async
  end
end
