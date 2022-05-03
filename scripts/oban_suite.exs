ExUnit.configure(trace: true)
ExUnit.start()

defmodule ObanSuite do
  use ExUnit.Case, async: false

  @signals [
    sigkill: "-9",
    sigterm: "-15"
  ]

  def run_test(signal) do
    Task.async fn ->
      System.shell("elixir oban_experiments.exs 2>&1")
      IO.inspect(result, IEx.inspect_opts)
    end
    Process.sleep(1_000)
    flag = Keyword.fetch!(@signals, signal)
    System.shell("pkill #{flag} -f oban_experiments")
    Process.sleep(1000)
  end

  test "sigkill", do: run_test(:sigkill)
  test "sigterm", do: run_test(:sigterm)
end
