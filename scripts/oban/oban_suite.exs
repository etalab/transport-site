# elixir oban_suite.exs
# see https://github.com/etalab/transport-site/pull/2365 for some context
ExUnit.start()

defmodule ObanSuite do
  use ExUnit.Case, async: false

  @signals [
    sigkill: "-9",
    sigterm: "-15"
  ]

  setup do
    {_result, 0} = System.shell("elixir oban_experiments.exs create_db 2>&1")

    on_exit(fn ->
      {result, 0} = System.shell("elixir oban_experiments.exs check 2>&1")
      IO.puts("After:")
      IO.puts(result)
    end)
  end

  def run_test(signal) do
    IO.puts("Testing #{signal}...")

    Task.async(fn ->
      {_result, _exit_code} = System.shell("elixir oban_experiments.exs run 2>&1")
      #      IO.inspect(result, IEx.inspect_opts)
    end)

    Process.sleep(1_000)
    flag = Keyword.fetch!(@signals, signal)
    System.shell("pkill #{flag} -f oban_experiments")
    Process.sleep(1000)
  end

  test "sigkill", do: run_test(:sigkill)
  test "sigterm", do: run_test(:sigterm)
end
