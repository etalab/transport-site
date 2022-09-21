defmodule TransportWeb.Plugs.CustomSecureBrowserHeaders do
  @moduledoc """
    Call the put_secure_browser_headers Plug and add some CSP headers
  """

  def init(options), do: options

  def call(conn, _opts) do
    csp_headers = csp_headers(Application.fetch_env!(:transport, :app_env))
    Phoenix.Controller.put_secure_browser_headers(conn, csp_headers)
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
  def csp_headers(app_env) do
    csp_content =
      case app_env do
        :production ->
          """
          default-src 'none';
          connect-src *;
          font-src *;
          img-src 'self' data: https://api.mapbox.com https://static.data.gouv.fr https://www.data.gouv.fr;
          script-src 'self' 'unsafe-eval' 'unsafe-inline' https://stats.data.gouv.fr/matomo.js;
          style-src 'self';
          report-uri #{Application.fetch_env!(:sentry, :csp_url)}
          """

        :staging ->
          # prochainement is currently making calls to both data.gouv.fr and demo.data.gouv.fr, which is probably not expected
          """
            default-src 'none';
            connect-src *;
            font-src *;
            img-src 'self' data: https://api.mapbox.com https://static.data.gouv.fr https://demo-static.data.gouv.fr https://www.data.gouv.fr https://demo.data.gouv.fr;
            script-src 'self' 'unsafe-eval' 'unsafe-inline' https://stats.data.gouv.fr/matomo.js;
            style-src 'self';
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
