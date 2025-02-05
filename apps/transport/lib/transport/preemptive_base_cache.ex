defmodule Transport.PreemptiveBaseCache do
  @moduledoc """
  Common code for preemptive caches. This module is a macro that generates a GenServer,
  which will populate a cache at regular intervals (similar to a cron job).

  Usage:
  ```
  use Transport.PreemptiveBaseCache,
    first_run: 0,
    job_delay: :timer.seconds(300),
    cache_ttl: :timer.seconds(700)
  ```
  The module in which it is used must implement the `populate_cache/0` function, that will be regularly called.

  - First run indicates the time to wait before the first run of the job between the start of the application and the first run.
  - Job delay indicates the time to wait between each run of the job.
  - Cache TTL indicates the time to keep the cache alive.
  """
  defmacro __using__(opts) do
    quote do
      use GenServer

      @first_run unquote(opts[:first_run])
      @job_delay unquote(opts[:job_delay])
      @cache_ttl unquote(opts[:cache_ttl])

      def cache_ttl, do: @cache_ttl

      def start_link(_opts) do
        GenServer.start_link(__MODULE__, %{})
      end

      def init(state) do
        schedule_next_occurrence(@first_run)

        {:ok, state}
      end

      def schedule_next_occurrence(delay) do
        Process.send_after(self(), :tick, delay)
      end

      def handle_info(:tick, state) do
        schedule_next_occurrence(@job_delay)
        populate_cache()
        {:noreply, state}
      end
    end
  end
end
