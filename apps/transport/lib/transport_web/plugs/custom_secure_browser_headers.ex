defmodule TransportWeb.Plugs.CustomSecureBrowserHeaders do
  @moduledoc """
  Call the put_secure_browser_headers Plug and add some CSP headers
  """

  def init(options), do: options

  defp generate_nonce(size \\ 10), do: size |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def call(conn, _opts) do
    nonce = generate_nonce()
    csp_headers = csp_headers(Mix.env(), Application.fetch_env!(:transport, :app_env), nonce)
    headers = Map.merge(csp_headers, %{"x-frame-options" => "DENY"})

    conn
    # used by the phoenix LivedDashboard to allow secure inlined CSS
    |> Plug.Conn.assign(:csp_nonce_value, nonce)
    |> Plug.Conn.put_session(:csp_nonce_value, nonce)
    |> Phoenix.Controller.put_secure_browser_headers(headers)
  end

  @doc """
  Returns content-security-policy headers for an app environment.

  iex> nonce = "foo"
  iex> match?(%{"content-security-policy" => _csp_content}, csp_headers(:prod, :production, nonce))
  true
  iex> match?(%{"content-security-policy" => _csp_content}, csp_headers(:prod, :staging, nonce))
  true
  iex> csp_headers(:prod, :staging, nonce) != csp_headers(:prod, :production, nonce)
  true
  iex> String.contains?("report-uri", csp_headers(:dev, :dev, nonce) |> Map.fetch!("content-security-policy"))
  false
  """
  def csp_headers(mix_env, app_env, nonce) do
    # https://github.com/vega/vega-embed/issues/1214#issuecomment-1670812445
    vega_hash_values =
      "'sha256-9uoGUaZm3j6W7+Fh2wfvjI8P7zXcclRw5tVUu3qKZa0=' 'sha256-MmUum7+PiN7Rz79EUMm0OmUFWjCx6NZ97rdjoIbTnAg='"

    policy =
      %{
        "default-src" => "'none'",
        "connect-src" => "*",
        "font-src" => "*",
        "frame-ancestors" => "'none'",
        "img-src" =>
          "'self' data: https://api.mapbox.com https://data.geopf.fr https://static.data.gouv.fr https://www.data.gouv.fr https://*.dmcdn.net #{Transport.S3.permanent_url(:logos)}",
        "script-src" => "'self' 'unsafe-eval' 'unsafe-inline' https://stats.data.gouv.fr/matomo.js",
        "frame-src" => "https://*.dailymotion.com",
        "style-src" => "'self' 'nonce-#{nonce}' #{vega_hash_values}",
        "report-uri" => ""
      }
      |> Enum.map(fn {directive, value} ->
        extra = " #{additional_content(directive, mix_env, app_env) |> String.trim()}"
        {directive, value <> extra}
      end)
      |> Enum.reject(fn {_, v} -> v == "" end)
      |> Enum.map_join(";", fn {k, v} -> "#{k} #{v}" end)

    %{"content-security-policy" => policy}
  end

  defp additional_content("img-src", mix_env, app_env) do
    if mix_env == :dev or app_env == :staging do
      "https://demo-static.data.gouv.fr https://demo.data.gouv.fr"
    else
      ""
    end
  end

  defp additional_content("report-uri", _mix_env, app_env) when app_env in [:production, :staging] do
    Application.fetch_env!(:sentry, :csp_url)
  end

  defp additional_content(_directive, _mix_env, _app_env) do
    ""
  end
end
