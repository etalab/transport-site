defmodule TransportWeb.BuildTest do
  use ExUnit.Case
  import ExUnit.CaptureIO

  def tool_versions do
    File.read!("../../.tool-versions")
  end

  def asdf_elixir_version do
    [[_, version]] = Regex.scan(~r/elixir (\d+\.\d+\.\d+)/, tool_versions())
    version
  end

  def asdf_erlang_version(return_full_version \\ false) do
    [[_, full_version, major_version]] = Regex.scan(~r/^erlang ((\d+)\..*$)/m, tool_versions())

    if return_full_version do
      full_version
    else
      major_version
    end
  end

  def asdf_nodejs_release do
    [[_, version]] = Regex.scan(~r/nodejs (\d+\.\d+\.\d+)/, tool_versions())
    version
  end

  # Skip next test on Mac M1, where it will always (currently) fail
  # See https://github.com/etalab/transport-site/issues/2520
  if Transport.Platform.apple_silicon?(), do: @tag(:pending)

  test "rambo rust wrapper compiles and runs" do
    {:ok, %{out: "hello\n"}} = Rambo.run("echo", ["hello"])
  end

  test "rambo remains on hex version (not the ARM-compatible fork)" do
    # NOTE: on ARM architecture (e.g. Mac M1 etc), a local commit can alter `mix.lock`,
    # and we want to detect cases where this happens. See:
    # https://github.com/etalab/transport-site/issues/3820
    # The test has to take the git-stored version of `mix.lock` and assert on its content,
    # because the CI doesn't run ARM and `mix deps.get` will overwrite `mix.lock` at the moment
    {output, 0} = System.cmd("git", ["show", "HEAD:../../mix.lock"])
    {{%{rambo: rambo}, []}, _log} = with_io(:stderr, fn -> Code.eval_string(output) end)

    # if this test fails, it may be because someone with a Mac M1 unintentionally committed `mix.lock` change
    # related to a Rambo-tweak, see https://github.com/etalab/transport-site/blob/61eabf185e71b7670e5d750048714636f85c5e58/apps/transport/mix.exs#L99-L111
    assert rambo |> elem(0) == :hex
  end

  test "make sure Elixir version is same for asdf & CI" do
    assert System.version() == asdf_elixir_version()
  end

  test "make sure major OTP version is same for asdf & CI" do
    assert System.otp_release() == asdf_erlang_version()
  end

  test "make sure full OTP version is same for asdf & Docker image" do
    # NOTE: the previous tests only check the major + minor (24.0), not the build version (24.0.3)
    # Getting the build version of OTP is tricky, but useful because in the past, we had differences.
    # We really want to have the same version as much as possible to avoid complicated debugging stories.
    content = File.read!("../../Dockerfile")
    [[_, production_version]] = Regex.scan(~r/FROM.*erlang\-([\d\.]+)/, content)

    assert asdf_erlang_version(true) == production_version
  end

  test "make sure NodeJS version is same for asdf & CI" do
    {output, 0} = System.cmd("node", ["--version"])
    assert output |> String.trim() == "v" <> asdf_nodejs_release()
  end

  test "make sure Docker image is same for production & CI" do
    content = File.read!("../../Dockerfile")
    [[_, production_version]] = Regex.scan(~r/FROM (ghcr.*)/, content)

    content = File.read!("../../Dockerfile.dev")
    [[_, docker_compose_version]] = Regex.scan(~r/FROM (ghcr.*)/, content)

    content = File.read!("../../.circleci/config.yml")
    [[_, ci_version]] = Regex.scan(~r/(ghcr.*)/, content)

    assert ci_version == production_version
    assert ci_version == docker_compose_version
  end

  def js_out_of_date_message(dep) do
    "Your javascript package for #{dep} is out of date.\nPlease update it with:\n\ncd apps/transport/client && yarn upgrade #{dep}"
  end

  # figuring out you have forgotten to upgrade the assets can be tricky, so we add a little reminder here
  test "make sure LiveView client assets are up to date" do
    {output, 0} = System.cmd("yarn", ["list", "--pattern", "phoenix_live_view"], cd: "client")
    [[_, version]] = Regex.scan(~r/@(\d+\.\d+\.\d+)/, output)

    expected_version = Application.spec(:phoenix_live_view, :vsn)

    assert(
      version == expected_version |> to_string(),
      js_out_of_date_message(:phoenix_live_view)
    )

    # extra fix for https://github.com/etalab/transport-site/issues/1938
    # problem appears only locally, so probably linked to webpack or similar
    lock_file =
      "#{__DIR__}/../client/yarn.lock"
      |> File.read!()
      |> String.replace("\n", "")

    [
      [_, "phoenix", phoenix_yarn_version],
      [_, "phoenix_html", phoenix_html_yarn_version],
      [_, "phoenix_live_view", phoenix_yarn_live_view_version]
    ] = Regex.scan(~r/deps\/(phoenix_html|phoenix_live_view|phoenix)":  version "([^"]+)"/, lock_file)

    assert phoenix_yarn_version == :phoenix |> Application.spec(:vsn) |> to_string(), js_out_of_date_message(:phoenix)

    assert phoenix_html_yarn_version == :phoenix_html |> Application.spec(:vsn) |> to_string(),
           js_out_of_date_message(:phoenix_html)

    assert phoenix_yarn_live_view_version == :phoenix_live_view |> Application.spec(:vsn) |> to_string(),
           js_out_of_date_message(:phoenix_live_view)
  end
end
