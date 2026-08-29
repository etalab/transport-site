defmodule Transport.AppConfig.ProdTest do
  use ExUnit.Case, async: true

  alias Transport.AppConfig.Prod

  test "wires the provided env" do
    config =
      Prod.build(:prod, %{
        "CLOAK_KEY" => "k",
        "SENTRY_DSN" => "d",
        "SENTRY_CSP_URL" => "c",
        "PHOENIX_DDOS_SAFELIST_IPS" => "1.2.3.4|5.6.7.8",
        "PHOENIX_DDOS_MAX_2MIN_REQUESTS" => "42"
      })

    assert config[:transport][:cloak_key] == "k"
    assert config[:transport][:s3_buckets][:history] == "resource-history-prod"
    assert config[:logger] == [level: :info]
    assert config[:sentry] == [dsn: "d", csp_url: "c"]
    assert config[:phoenix_ddos][:safelist_ips] == ["1.2.3.4", "5.6.7.8"]
    assert [{PhoenixDDoS.IpRateLimit, [allowed: 42, period: {2, :minutes}]} | _] = config[:phoenix_ddos][:protections]
  end

  test "raises when a required variable is missing, naming it without leaking env" do
    assert_raise RuntimeError, ~r/"CLOAK_KEY" is required/, fn -> Prod.build(:prod, %{}) end
  end

  test "optional knobs fall back to defaults" do
    config = Prod.build(:prod, %{"CLOAK_KEY" => "k", "SENTRY_DSN" => "d"})

    assert config[:sentry][:csp_url] == nil
    assert config[:phoenix_ddos][:safelist_ips] == []
    assert [{_, [{:allowed, 500} | _]}, {_, [{:allowed, 10_000} | _]} | _] = config[:phoenix_ddos][:protections]
  end
end
