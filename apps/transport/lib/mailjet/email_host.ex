defmodule Transport.RuntimeConfig.EmailHost do
  # See https://github.com/etalab/transport-site/issues/2154

  def email_host(endpoint \\ TransportWeb.Endpoint) do
    case Mix.env() do
      :dev ->
        # this will bring the correct scheme, host, and port
        endpoint.url()

      :test ->
        endpoint.url()
        |> URI.parse()
        # to help automate catching emails that are not properly configured, we're overriding
        |> URI.merge(%URI{host: "email.localhost"})

      :prod ->
        host =
          case Application.fetch_env!(:transport, :app_env) do
            # NOTE: in the future, we'll avoid hardcoding here, and use a mandatory
            # EMAIL_DOMAIN_NAME of sorts
            # https://github.com/etalab/transport-site/issues/1688
            :staging -> "prochainement.transport.data.gouv.fr"
            :prod -> "transport.data.gouv.fr"
          end

        endpoint.url()
        |> URI.parse()
        |> URI.merge(%URI{host: host})
    end
  end
end
