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

  def fetch(cache_key, value_fn, cache_name \\ Transport.Application.cache_name()) do
    comp_fn = fn key ->
      Logger.info("Generating cached value for key #{key}")

      try do
        {:commit, value_fn.()}
      rescue
        e ->
          # NOTE: if an error occurs inside the value_fn computation, then
          # we want to track it down specifically and re-raise, without
          # re-calling the value function
          {:error, {:computation_error, e, __STACKTRACE__}}
      end
    end

    {operation, result} = Cachex.fetch(cache_name, cache_key, comp_fn, ttl: :timer.seconds(60))

    case operation do
      :ok ->
        Logger.info("Value for key #{cache_key} served from cache")
        result

      :commit ->
        Logger.info("Value for key #{cache_key} regenerated")
        result

      :error ->
        case result do
          {:computation_error, computation_error, computation_error_stacktrace} ->
            Logger.error("The computation function failed during cached query for key #{cache_key}. Re-raising.")
            reraise(computation_error, computation_error_stacktrace)

          _ ->
            # here we assume we have a technical (cache-oriented) error, and we'll try to evaluate the function again
            Logger.error(
              "Cache error #{result |> inspect} while handling key #{cache_key} - attempting to evaluate without cache"
            )

            # NOTE: if this occurs, we'll need to propagate "result" into it, instead of hiding the underlying details,
            # but I'm not 100% sure how to do it reliably yet
            Sentry.capture_message("unable_to_reach_cache")
            value_fn.()
        end
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
