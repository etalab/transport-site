defmodule Transport.AppConfig.Prod do
  @moduledoc "Builds part of the `:prod` config, wired into runtime.exs. See https://github.com/etalab/transport-site/issues/3688"

  @s3_buckets %{
    history: "resource-history-prod",
    on_demand_validation: "on-demand-validation-prod",
    gtfs_diff: "gtfs-diff-prod",
    logos: "logos-prod",
    aggregates: "aggregates-prod"
  }

  @spec build(:prod, map()) :: [{atom(), keyword()}]
  def build(:prod, env) do
    [
      {:transport, [cloak_key: fetch!(env, "CLOAK_KEY"), s3_buckets: @s3_buckets]},
      {:sentry, [dsn: fetch!(env, "SENTRY_DSN"), csp_url: Map.get(env, "SENTRY_CSP_URL")]},
      {:phoenix_ddos,
       [
         safelist_ips: ip_list(env, "PHOENIX_DDOS_SAFELIST_IPS"),
         blocklist_ips: ip_list(env, "PHOENIX_DDOS_BLOCKLIST_IPS"),
         protections: [
           {PhoenixDDoS.IpRateLimit, allowed: int(env, "PHOENIX_DDOS_MAX_2MIN_REQUESTS", 500), period: {2, :minutes}},
           {PhoenixDDoS.IpRateLimit, allowed: int(env, "PHOENIX_DDOS_MAX_1HOUR_REQUESTS", 10_000), period: {1, :hour}},
           {PhoenixDDoS.IpRateLimitPerRequestPath,
            request_paths: [{:get, "/login"}], allowed: 5, period: {30, :seconds}},
           {PhoenixDDoS.IpRateLimitPerRequestPath,
            request_paths: [{:post, "/send_mail"}], allowed: 1, period: {30, :seconds}}
         ]
       ]},
      {:logger, [level: :info]}
    ]
  end

  # Name the missing key only — don't leak env secrets into the exception.
  defp fetch!(env, key) do
    case env do
      %{^key => value} -> value
      _ -> raise "environment variable #{inspect(key)} is required for :prod but is not set"
    end
  end

  defp int(env, key, default), do: env |> Map.get(key, to_string(default)) |> String.to_integer()
  defp ip_list(env, key), do: env |> Map.get(key, "") |> String.split("|") |> Enum.reject(&(&1 == ""))
end
