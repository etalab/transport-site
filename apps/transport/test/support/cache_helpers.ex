defmodule Transport.Test.CacheHelpers do
  @moduledoc """
  Tests run with `Transport.Cache.Null`, which caches nothing. For tests of the caching itself:
  `setup {Transport.Test.CacheHelpers, :use_real_cache}`, in `async: false` modules only since
  it changes the global config.
  """
  import ExUnit.Callbacks, only: [on_exit: 1]

  def use_real_cache(_context) do
    old_value = Application.fetch_env!(:transport, :cache_impl)
    Application.put_env(:transport, :cache_impl, Transport.Cache.Cachex)
    on_exit(fn -> Application.put_env(:transport, :cache_impl, old_value) end)
  end
end
