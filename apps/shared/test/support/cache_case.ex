defmodule Shared.CacheCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require access to the Cachex cache.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      use ExUnit.Case, async: false
      import Shared.Application, only: [cache_name: 0]
      import Mox

      setup :verify_on_exit!
      setup :set_mox_from_context

      setup do
        Cachex.clear(cache_name())
        on_exit(fn -> Cachex.clear(cache_name()) end)
      end

      def assert_cache_key_has_ttl(cache_key, expected_ttl \\ 300) do
        assert_in_delta Cachex.ttl!(cache_name(), cache_key), :timer.seconds(expected_ttl), :timer.seconds(1)
      end
    end
  end
end
