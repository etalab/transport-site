defmodule Mix.Tasks.Clever.Logs do
  @moduledoc """
  The CleverCloud logs command currently has strong limitations, including a maximum of
  1000 lines of logs per command invocation (https://github.com/CleverCloud/clever-tools/issues/429)
  and a lack of auto-pagination.

  This task provides a minimal ability to fetch logs from the platform.
  """

  require Logger
  use Mix.Task

  def fetch_logs(app, start_time, end_time) do
    cmd_args = [
      "logs",
      "--alias",
      app,
      "--since",
      start_time |> DateTime.to_iso8601(),
      "--before",
      end_time |> DateTime.to_iso8601()
    ]

    Logger.info("Running clever #{cmd_args |> Enum.join(" ")}")
    {output, _exit_code = 0} = System.cmd("clever", cmd_args)

    logs = output |> String.split("\n")

    # safety check to reduce the risk of missing logs
    if Enum.count(logs) > 990 do
      Mix.raise(
        "Fetching near or more than 1000 lines of logs at once means you are going to miss some data (https://github.com/CleverCloud/clever-tools/issues/429).\n\nPlease reduce the span_size_in_seconds!"
      )
    end

    logs
  end

  def run(_args) do
    start_time = DateTime.utc_now() |> DateTime.add((-1 * 60 * 60 * 24) |> round(), :second)
    app = "transport-site"
    span_size_in_seconds = 3 * 60

    logs =
      Stream.resource(
        fn -> %{start_time: start_time, seen_lines: MapSet.new()} end,
        fn state ->
          case state.start_time > DateTime.utc_now() do
            true ->
              {:halt, nil}

            false ->
              end_time = DateTime.add(state.start_time, span_size_in_seconds, :second)
              logs = fetch_logs(app, state.start_time, end_time)

              {_seen, unseen} = logs |> Enum.split_with(&MapSet.member?(state.seen_lines, &1))

              {
                logs,
                state
                |> Map.put(:start_time, end_time)
                |> Map.put(:seen_lines, state.seen_lines |> MapSet.union(MapSet.new(unseen)))
              }
          end
        end,
        fn _ -> nil end
      )

    logs
    |> Stream.each(&IO.puts(&1))
    |> Stream.run()
  end
end
