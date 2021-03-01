defmodule Transport.Cache.API do
  @moduledoc """
  This behaviour defines the API for caching, with alternative implementations.
  """

  @callback fetch(cache_key :: binary(), fun()) :: any

  defp impl, do: Application.get_env(:transport, :cache_impl)

  def fetch(cache_key, comp_fn), do: impl().fetch(cache_key, comp_fn)
end

defmodule Transport.Cache.Cachex do
  @moduledoc """
  Cache utility for transport
  """
  @behaviour Transport.Cache.API

  require Logger

  def fetch(cache_key, value_fn) do
    comp_fn = fn key ->
      Logger.info("Generating cached value for key #{key}")
      {:commit, value_fn.()}
    end

    cache_name = Transport.Application.cache_name()

    {operation, result} = Cachex.fetch(cache_name, cache_key, comp_fn, ttl: :timer.seconds(60))

    case operation do
      :ok ->
        Logger.info("Value for key #{cache_key} served from cache")
        result

      :commit ->
        Logger.info("Value for key #{cache_key} regenerated")
        result

      :error ->
        # should normally not occur, but as a safeguard we'll still try to evaluate the computation
        Logger.error("Cache error while handling key #{cache_key} - attempting to evaluate without cache")
        Sentry.capture_message("unable_to_reach_cache")
        value_fn.()
    end
  end
end

defmodule Transport.Cache.Null do
  @moduledoc """
  A non-caching cache to be used by tests mostly.
  """
  @behaviour Transport.Cache.API

  def fetch(_cache_key, value_fn), do: value_fn.()
end
