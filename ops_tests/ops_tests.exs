# run with `elixir ops_tests/ops_tests.exs`
# this is a starting point to implement infrastructure & DNS testing
ExUnit.start()

Mix.install([
  {:req, "~> 0.4.8"},
  {:dns, "~> 2.4.0"}
])

defmodule Transport.OpsTests do
  use ExUnit.Case, async: true

  # See https://developers.clever-cloud.com/doc/administrate/domain-names/#your-application-runs-in-the-europeparis-par-zone
  @domain_name "transport.data.gouv.fr"
  @clever_cloud_ip_addresses [
    {46, 252, 181, 103},
    {46, 252, 181, 104},
    {185, 42, 117, 108},
    {185, 42, 117, 109}
  ]

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

  test "redirects from www to non-www" do
    assert_redirect(from: "https://www.#{@domain_name}", to: "https://#{@domain_name}/")
  end

  describe "Check DNS records" do
    test "main A/CNAME records" do
      {:ok, ips} = DNS.resolve(@domain_name, :a)
      assert MapSet.new(ips) == MapSet.new(@clever_cloud_ip_addresses)

      # CNAMEs to Clever Cloud
      [
        "prochainement",
        "proxy",
        "proxy.prochainement",
        "validation",
        "workers",
        "workers.prochainement",
        "www"
      ]
      |> Enum.each(fn subdomain ->
        record = "#{subdomain}.#{@domain_name}"
        assert {:ok, [~c"domain.par.clever-cloud.com"]} == DNS.resolve(record, :cname), "Wrong DNS record for #{record}"
      end)

      # Satellite websites
      assert {:ok, [~c"transport-blog.netlify.app"]} == DNS.resolve("blog.#{@domain_name}", :cname)
      assert {:ok, [~c"transport-contribuer.netlify.app"]} == DNS.resolve("contribuer.#{@domain_name}", :cname)
      assert {:ok, [~c"hosting.gitbook.com"]} == DNS.resolve("doc.#{@domain_name}", :cname)
      assert {:ok, [~c"stats.uptimerobot.com"]} == DNS.resolve("status.#{@domain_name}", :cname)
    end
  end

  def get_header!(headers, header) do
    {_header, [value]} = Enum.find(headers, fn {k, _} -> k == header end)
    value
  end

  def assert_redirect(from: url, to: target_url) do
    %Req.Response{status: 301, headers: headers} = Req.get!(url, redirect: false)
    assert get_header!(headers, "location") == target_url
  end
end
