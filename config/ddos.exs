import Config

# `phoenix_ddos` is called in our own Plug `TransportWeb.Plugs.RateLimiter`
config :phoenix_ddos,
  safelist_ips: "PHOENIX_DDOS_SAFELIST_IPS" |> System.get_env("") |> String.split("|") |> Enum.reject(&(&1 == "")),
  blocklist_ips: "PHOENIX_DDOS_BLOCKLIST_IPS" |> System.get_env("") |> String.split("|") |> Enum.reject(&(&1 == "")),
  protections: [
    # ip rate limit
    {PhoenixDDoS.IpRateLimit,
     allowed: "PHOENIX_DDOS_MAX_2MIN_REQUESTS" |> System.get_env("500") |> Integer.parse() |> elem(0),
     period: {2, :minutes}},
    {PhoenixDDoS.IpRateLimit,
     allowed: "PHOENIX_DDOS_MAX_1HOUR_REQUESTS" |> System.get_env("10000") |> Integer.parse() |> elem(0),
     period: {1, :hour}},
    # ip rate limit on specific request_path
    {PhoenixDDoS.IpRateLimitPerRequestPath, request_paths: [{:get, "/login"}], allowed: 5, period: {30, :seconds}},
    {PhoenixDDoS.IpRateLimitPerRequestPath, request_paths: [{:post, "/send_mail"}], allowed: 1, period: {30, :seconds}}
  ]
