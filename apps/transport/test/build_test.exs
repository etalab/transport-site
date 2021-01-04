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

  def get_from(file) do
    file
    |> File.read!()
    |> String.split("\n")
    |> List.first()
  end

  test "make sure Dockerfile.dev base image is up to date" do
    assert get_from("../../Dockerfile.dev") == get_from("../../Dockerfile")
  end
end
