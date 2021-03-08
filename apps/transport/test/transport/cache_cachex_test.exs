defmodule Transport.Cache.Cachex.Test do
  # make sure to keep UUID for cache keys so that async can be kept in place
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  def build_unique_cache_key, do: Ecto.UUID.generate()

  test "it caches values provided in Cachex cache" do
    unique_cache_key = build_unique_cache_key()
    initial_value = [hello: "world"]

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> initial_value end)
    assert Cachex.get!(:transport, unique_cache_key) == initial_value

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> "something else" end)
    assert Cachex.get!(:transport, unique_cache_key) == [hello: "world"]
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

  test "it invokes the computation function directly in case of technical cachex error" do
    unique_cache_key = build_unique_cache_key()

    logs =
      capture_log(fn ->
        data = Transport.Cache.Cachex.fetch(unique_cache_key, fn -> "some data" end, :non_existent_cache)
        assert data == "some data"
      end)

    assert logs =~ "Cache error :no_cache"
  end
end
