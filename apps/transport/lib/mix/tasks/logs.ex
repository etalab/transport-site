defmodule Mix.Tasks.Clever.Logs do
  @shortdoc "Fetches logs from CleverCloud"

  @moduledoc """
  The CleverCloud logs command currently has strong limitations, including a maximum of
  1000 lines of logs per command invocation (https://github.com/CleverCloud/clever-tools/issues/429)
  and a lack of auto-pagination.

  This mix task provides a minimal ability to fetch logs from the platform.

  How to use:

  ```
  mix clever.logs --since "2021-01-25T04:00:00Z" --before "2021-01-25T04:10:00Z" --alias "the-app"
  ```

  The switches mimic the CleverCloud logs ones:
  * `--since`: start time (ISO8601 Z). Defaults to "24 hours ago".
  * `--before`: end time (ISO8601 Z). Defaults to "now".
  * `--alias`: name of the CleverCloud app.
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
    {output, _exit_code = 0} = System.cmd("clever", cmd_args, stderr_to_stdout: true)

    logs = output |> String.split("\n")

    # safety check to reduce the risk of missing logs
    if Enum.count(logs) > 990 do
      Mix.raise(
        "Fetching near or more than 1000 lines of logs at once means you are going to miss some data (https://github.com/CleverCloud/clever-tools/issues/429).\n\nPlease reduce the span_size_in_seconds!"
      )
    end

    logs
  end

  def default_start_time do
    now = DateTime.utc_now()
    span = round(-1 * 60 * 60 * 24)

    now
    |> DateTime.add(span, :second)
    |> DateTime.to_iso8601()
  end

  def default_end_time, do: DateTime.utc_now() |> DateTime.to_iso8601()

  def prep_args(args) do
    {options, _rest} = OptionParser.parse!(args, strict: [since: :string, before: :string, alias: :string])

    options =
      options
      |> Keyword.put_new(
        :since,
        default_start_time()
      )
      |> Keyword.put_new(
        :before,
        default_end_time()
      )

    {:ok, start_time, 0} = options[:since] |> DateTime.from_iso8601()
    {:ok, end_time, 0} = options[:before] |> DateTime.from_iso8601()

    unless options[:alias] do
      Mix.raise("Switch --alias is required")
    end

    {start_time, end_time, options |> Keyword.fetch!(:alias)}
  end

  def run(args) do
    {start_time, end_time, app} = prep_args(args)

    Logger.info("Fetching logs from #{start_time} to #{end_time}")

    span_size_in_seconds = 3 * 60

    logs =
      Stream.resource(
        fn -> %{start_time: start_time, seen_lines: MapSet.new()} end,
        fn state ->
          if state.start_time > end_time do
            {:halt, nil}
          else
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
