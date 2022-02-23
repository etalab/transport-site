# run with `elixir ops_tests/ops_tests.exs`
# this is a starting point to implement infrastructure & DNS testing
ExUnit.start()

Mix.install([
  {:req, "~> 0.2.1"}
])

defmodule Transport.OpsTests do
  use ExUnit.Case

  def get_header!(headers, header) do
    {_header, value} =
      headers
      |> Enum.find(fn {k, _} -> k == header end)

    value
  end

  def assert_redirect(from: url, to: target_url) do
    %{status: 301, headers: headers} =
      Req.build(:get, url)
      |> Req.run!()

    assert get_header!(headers, "location") == target_url
  end

  test "correct DOMAIN_NAME for prod-worker" do
    assert_redirect(
      from: "http://workers.transport.data.gouv.fr",
      to: "https://workers.transport.data.gouv.fr/"
    )
  end

  test "correct DOMAIN_NAME for staging-worker" do
    assert_redirect(
      from: "http://workers.prochainement.transport.data.gouv.fr",
      to: "https://workers.prochainement.transport.data.gouv.fr/"
    )
  end
end
