defmodule Transport.Cache.Cachex.Test do
  # make sure to keep UUID for cache keys so that async can be kept in place
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  defmodule SomeCustomException do
    defexception message: "Oh noes! A custom error occurred!"
  end

  test "safeguard code to ensure Cachex does not change of behaviour on their future upgrades" do
    # see relevant parts of code:
    # * https://github.com/whitfin/cachex/blob/836578ec452bfa6eba3c3159123cccdc9038127e/lib/cachex/services/courier.ex#L73-L78
    # * https://github.com/whitfin/cachex/blob/836578ec452bfa6eba3c3159123cccdc9038127e/lib/cachex/actions.ex#L85

    # a technical error is provided with the following tuple:
    {:error, :no_cache} = Cachex.fetch(:pok, "some-key-001", fn _ -> "data" end, ttl: :timer.seconds(0))

    # a regular data change comes out like this:
    {:commit, "data"} = Cachex.fetch(:transport, "some-key-002", fn _ -> "data" end, ttl: :timer.seconds(0))

    # an error raised inside the computation callback gives:
    {:error, "foobar"} = Cachex.fetch(:transport, "some-key-003", fn _ -> raise "foobar" end, ttl: :timer.seconds(0))

    # catching the error ourselves to allow re-raising
    # (inspired by https://github.com/whitfin/cachex/issues/252, not merged at time of writing)
    {:error, {:computation_error, captured_error = %SomeCustomException{}, captured_stacktrace}} =
      Cachex.fetch(:transport, "some-key-004", fn _ ->
        try do
          raise SomeCustomException
        rescue
          e -> {:error, {:computation_error, e, __STACKTRACE__}}
        end
      end)

    assert_raise(SomeCustomException, fn ->
      Kernel.reraise(captured_error, captured_stacktrace)
    end)
  end

  test "it caches values provided in Cachex cache" do
    unique_cache_key = Ecto.UUID.generate()
    initial_value = [hello: "world"]

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> initial_value end)
    assert Cachex.get!(:transport, unique_cache_key) == initial_value

    Transport.Cache.Cachex.fetch(unique_cache_key, fn -> "something else" end)
    assert Cachex.get!(:transport, unique_cache_key) == [hello: "world"]
  end

  # TODO: wrap the computation function with a rescue, and make sure to
  # avoid duplicate invoke since there is no point
  test "it bubbles up errors occurring inside the computation function"

  test "it invoke the computation function directly in case of technical cachex error"


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
