defmodule Transport.Cache.Cachex.Test do
  use ExUnit.Case, async: false
  import ExUnit.CaptureLog

  test "it caches values provided in Cachex cache" do
    unique_cache_key = Ecto.UUID.generate()
    initial_value = [hello: "world"]

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> initial_value end)
    assert Cachex.get!(:transport, unique_cache_key) == initial_value

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> "something else" end)
    assert Cachex.get!(:transport, unique_cache_key) == [hello: "world"]
  end

  test "it handles errors as best as it can" do
    unique_cache_key = Ecto.UUID.generate()

    # Fake an error by raising from the callback. It should be re-raised.
    # A better test would call an non-existing Cachex cache
    logs =
      capture_log(fn ->
        assert_raise(RuntimeError, fn ->
          Transport.Cache.Cachex.fetch(unique_cache_key, fn -> raise "STOP" end)
        end)
      end)

    logs = logs |> String.split("\n")
    assert logs |> Enum.at(0) =~ "Cache error while handling key"
  end
end
