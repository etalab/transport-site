defmodule Transport.RuntimeConfigurationTest do
  use ExUnit.Case, async: true
  import Mox
  setup :verify_on_exit!

  test ":prod config" do
    mox = Transport.SystemEnv.Mock

    mox
    |> expect(:get_env, fn "WORKER" -> "1" end)
    |> expect(:get_env, fn "WEBSERVER" -> "1" end)

    assert mox
           |> Transport.RuntimeConfiguration.build_config(:prod) ==
             {"1", "1"}
  end
end
