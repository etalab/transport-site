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

  def fetch_log_page(app, end_time) do
    # must be tuned so that we get close to 1000 logs at each call to maximize throughput
    span_size_in_seconds = 10 * 60
    start_time = DateTime.add(end_time, -1 * span_size_in_seconds, :second)

    cmd_args = [
      "logs",
      "--alias",
      app,
      "--since",
      start_time |> DateTime.to_iso8601(),
      "--before",
      end_time |> DateTime.to_iso8601()
    ]

    Logger.info("Extracting logs with clever #{cmd_args |> Enum.join(" ")}")
    {output, _exit_code = 0} = System.cmd("clever", cmd_args, stderr_to_stdout: true)

    logs =
      output
      |> String.split("\n")
      |> Enum.map(&String.trim/1)
      |> Enum.filter(&(&1 != ""))
      |> Enum.reject(&String.starts_with?(&1, "Waiting for application logs"))

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

  def build_next_end_time(logs) do
    timestamped_log = logs |> Enum.at(0)
    timestamp = timestamped_log |> String.split(" ") |> List.first() |> String.trim_trailing(":")
    {:ok, timestamp, 0} = DateTime.from_iso8601(timestamp)
    DateTime.add(timestamp, +1, :second)
  end

  def extract_log_page_and_update_state(app, state) do
    logs = fetch_log_page(app, state.end_time)
    {_seen, unseen} = logs |> Enum.split_with(&MapSet.member?(state.seen_lines, &1))

    {
      logs |> Enum.reverse(),
      state
      |> Map.put(:end_time, build_next_end_time(logs))
      |> Map.put(:seen_lines, state.seen_lines |> MapSet.union(MapSet.new(unseen)))
    }
  end

  def run(args) do
    {original_start_time, original_end_time, app} = prep_args(args)

    Logger.info("Fetching logs from #{original_start_time} to #{original_end_time}")

    # extract the logs in backward fashion, because clever cloud CLI currently
    # treats the --before as the starting point
    logs =
      Stream.resource(
        fn -> %{end_time: original_end_time, seen_lines: MapSet.new()} end,
        fn state ->
          if state.end_time < original_start_time do
            {:halt, nil}
          else
            extract_log_page_and_update_state(app, state)
          end
        end,
        fn _ -> nil end
      )

    logs
    |> Enum.reverse()
    |> Enum.each(&IO.puts(&1))
  end
end
