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

  test "make sure Elixir version is same for asdf & CI" do
    assert System.version() == asdf_elixir_version()
  end

  test "make sure OTP version is same for asdf & CI" do
    assert System.otp_release() == asdf_elixir_release()
  end
end
