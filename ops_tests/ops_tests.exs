# run with `elixir ops_tests/ops_tests.exs`
# this is a starting point to implement infrastructure & DNS testing
ExUnit.start()

Mix.install([
  {:req, "~> 0.5.4"},
  {:dns, "~> 2.4.0"}
])

defmodule Transport.OpsTests do
  use ExUnit.Case, async: true

  # See https://developers.clever-cloud.com/doc/administrate/domain-names/#your-application-runs-in-the-europeparis-par-zone
  @domain_name "transport.data.gouv.fr"
  @clever_cloud_ip_addresses [
    {91, 208, 207, 214},
    {91, 208, 207, 215},
    {91, 208, 207, 216},
    {91, 208, 207, 217},
    {91, 208, 207, 218},
    {91, 208, 207, 220},
    {91, 208, 207, 221},
    {91, 208, 207, 222},
    {91, 208, 207, 223}
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

  test "redirects HTTP to HTTPS" do
    assert_redirect(from: "http://#{@domain_name}", to: "https://#{@domain_name}/")
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

    test "MX records" do
      {:ok, records} = DNS.resolve(@domain_name, :mx)
      assert MapSet.new([{10, ~c"mx1.alwaysdata.com"}, {20, ~c"mx2.alwaysdata.com"}]) == MapSet.new(records)
      assert {:ok, [{100, ~c"mx.sendgrid.net"}]} = DNS.resolve("front-mail.#{@domain_name}", :mx)
    end

    test "SPF, DKIM and DMARC" do
      # SPF
      {:ok, records} = DNS.resolve(@domain_name, :txt)

      assert Enum.member?(records, [
               ~c"v=spf1 include:spf.mailjet.com include:_spf.alwaysdata.com include:_spf.scw-tem.cloud include:servers.mcsv.net -all"
             ])

      assert {:ok, [[~c"v=spf1 include:sendgrid.net ~all"]]} = DNS.resolve("front-mail.#{@domain_name}", :txt)

      # DKIM
      assert {:ok, _} = DNS.resolve("37d278a7-e548-4029-a58d-111bdcf23d46._domainkey.#{@domain_name}", :txt)
      assert {:ok, _} = DNS.resolve("default._domainkey.#{@domain_name}", :txt)
      assert {:ok, _} = DNS.resolve("fnt._domainkey.#{@domain_name}", :txt)
      assert {:ok, _} = DNS.resolve("mailjet._domainkey.#{@domain_name}", :txt)
      assert {:ok, [~c"dkim2.mcsv.net"]} == DNS.resolve("k2._domainkey.#{@domain_name}", :cname)
      assert {:ok, [~c"dkim3.mcsv.net"]} == DNS.resolve("k3._domainkey.#{@domain_name}", :cname)

      # DMARC
      assert {:ok, [[~c"v=DMARC1;p=quarantine;"]]} == DNS.resolve("_dmarc.#{@domain_name}", :txt)
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
