defmodule Transport.Cache.Cachex.Test do
  # make sure to keep UUID for cache keys so that async can be kept in place
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  setup do
    on_exit(fn -> Cachex.clear(Transport.Application.cache_name()) end)
  end

  def build_unique_cache_key, do: Ecto.UUID.generate()

  test "it caches values provided in Cachex cache" do
    unique_cache_key = build_unique_cache_key()
    initial_value = [hello: "world"]

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> initial_value end)
    assert Cachex.get!(:transport, unique_cache_key) == initial_value

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> "something else" end)
    assert Cachex.get!(:transport, unique_cache_key) == [hello: "world"]

    assert_in_delta Cachex.ttl!(:transport, unique_cache_key), 60_000, 1000
  end

  test "custom expire" do
    unique_cache_key = build_unique_cache_key()
    initial_value = [hello: "world"]

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> initial_value end, :timer.seconds(45))

    assert Cachex.get!(:transport, unique_cache_key) == initial_value
    assert_in_delta Cachex.ttl!(:transport, unique_cache_key), 45_000, 1000
  end

  test "it bubbles up errors occurring inside the computation function" do
    logs =
      capture_log(fn ->
        assert_raise ArithmeticError, fn ->
          Transport.Cache.Cachex.fetch(build_unique_cache_key(), fn -> raise ArithmeticError end)
        end
      end)

    assert logs =~ "The computation function failed during cached query"
  end
end
