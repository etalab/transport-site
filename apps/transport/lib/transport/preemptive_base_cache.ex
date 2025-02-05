defmodule Transport.PreemptiveBaseCache do
  @moduledoc """
  Common code for preemptive caches
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

      def schedule_next_occurrence(delay \\ @job_delay) do
        Process.send_after(self(), :tick, delay)
      end

      def handle_info(:tick, state) do
        schedule_next_occurrence()
        populate_cache()
        {:noreply, state}
      end
    end
  end
end
