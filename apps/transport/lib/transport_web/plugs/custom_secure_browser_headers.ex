defmodule TransportWeb.Plugs.CustomSecureBrowserHeaders do
  @moduledoc """
  Call the put_secure_browser_headers Plug and add some CSP headers
  """

  def init(options), do: options

  defp generate_nonce(size \\ 10), do: size |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def call(conn, _opts) do
    nonce = generate_nonce()
    csp_headers = csp_headers(Application.fetch_env!(:transport, :app_env), nonce)
    headers = Map.merge(csp_headers, %{"x-frame-options" => "DENY"})

    conn
    # used by the phoenix LivedDashboard to allow secure inlined CSS
    |> Plug.Conn.assign(:csp_nonce_value, nonce)
    |> Plug.Conn.put_session(:csp_nonce_value, nonce)
    |> Phoenix.Controller.put_secure_browser_headers(headers)
  end

  @doc """
  Returns content-security-policy headers, depending on the APP_ENV value

  iex> csp_headers("")
  %{}
  iex> csp_headers("test")
  %{}
  iex> match?(%{"content-security-policy" => _csp_content}, csp_headers(:prod))
  true
  iex> match?(%{"content-security-policy" => _csp_content}, csp_headers(:staging))
  true
  """
  def csp_headers(app_env, nonce) do
    # https://github.com/vega/vega-embed/issues/1214#issuecomment-1670812445
    vega_hash_values =
      "'sha256-9uoGUaZm3j6W7+Fh2wfvjI8P7zXcclRw5tVUu3qKZa0=' 'sha256-MmUum7+PiN7Rz79EUMm0OmUFWjCx6NZ97rdjoIbTnAg='"

    logos_bucket_url = Transport.S3.permanent_url(:logos)

    csp_content =
      case app_env do
        :production ->
          """
          default-src 'none';
          connect-src *;
          font-src *;
          frame-ancestors 'none';
          img-src 'self' data: https://api.mapbox.com https://static.data.gouv.fr https://www.data.gouv.fr https://*.dmcdn.net #{logos_bucket_url};
          script-src 'self' 'unsafe-eval' 'unsafe-inline' https://stats.data.gouv.fr/matomo.js;
          frame-src https://*.dailymotion.com;
          style-src 'self' 'nonce-#{nonce}' #{vega_hash_values};
          report-uri #{Application.fetch_env!(:sentry, :csp_url)}
          """

        :staging ->
          # prochainement is currently making calls to both data.gouv.fr and demo.data.gouv.fr, which is probably not expected
          """
            default-src 'none';
            connect-src *;
            font-src *;
            frame-ancestors 'none';
            img-src 'self' data: https://api.mapbox.com https://static.data.gouv.fr https://demo-static.data.gouv.fr https://www.data.gouv.fr https://demo.data.gouv.fr https://*.dmcdn.net #{logos_bucket_url};
            script-src 'self' 'unsafe-eval' 'unsafe-inline' https://stats.data.gouv.fr/matomo.js;
            frame-src https://*.dailymotion.com;
            style-src 'self' 'nonce-#{nonce}' #{vega_hash_values};
            report-uri #{Application.fetch_env!(:sentry, :csp_url)}
          """

        _ ->
          nil
      end

    case csp_content do
      nil -> %{}
      csp_content -> %{"content-security-policy" => csp_content |> String.replace("\n", "")}
    end
  end
end
