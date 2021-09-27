defmodule TransportWeb.BuildTest do
  use ExUnit.Case

  def tool_versions do
    File.read!("../../.tool-versions")
  end

  def asdf_elixir_version do
    [[_, version]] = Regex.scan(~r/elixir (\d+\.\d+\.\d+)/, tool_versions())
    version
  end

  def asdf_elixir_release do
    [[_, version]] = Regex.scan(~r/erlang (\d+)\.\d/, tool_versions())
    version
  end

  def asdf_nodejs_release do
    [[_, version]] = Regex.scan(~r/nodejs (\d+\.\d+\.\d+)/, tool_versions())
    version
  end

  test "make sure Elixir version is same for asdf & CI" do
    assert System.version() == asdf_elixir_version()
  end

  test "make sure OTP version is same for asdf & CI" do
    assert System.otp_release() == asdf_elixir_release()
  end

  test "make sure NodeJS version is same for asdf & CI" do
    {output, 0} = System.cmd("node", ["--version"])
    assert output |> String.trim() == "v" <> asdf_nodejs_release()
  end

  test "make sure Docker image is same for production & CI" do
    content = File.read!("../../Dockerfile")
    [[_, production_version]] = Regex.scan(~r/FROM (.*)/, content)

    content = File.read!("../../Dockerfile.dev")
    [[_, docker_compose_version]] = Regex.scan(~r/FROM (.*)/, content)

    content = File.read!("../../.circleci/config.yml")
    [[_, ci_version]] = Regex.scan(~r/(betagouv\/transport.*)/, content)

    assert ci_version == production_version
    assert ci_version == docker_compose_version
  end

  # figuring out you have forgotten to upgrade the assets can be tricky, so we add a little reminder here
  test "make sure LiveView client assets are up to date" do
    {output, 0} = System.cmd("yarn", ["list", "--pattern", "phoenix_live_view"], cd: "client")
    [[_, version]] = Regex.scan(~r/@(\d+\.\d+\.\d+)/, output)

    expected_version = Application.spec(:phoenix_live_view, :vsn)

    assert(
      version == expected_version |> to_string(),
      "Your javascript package for phoenix_live_view is out of date.\nPlease update it with:\n\ncd apps/transport/client && yarn upgrade phoenix_live_view"
    )
  end
end
