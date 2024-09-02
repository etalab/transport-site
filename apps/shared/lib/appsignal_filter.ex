defmodule TransportWeb.Plugs.AppSignalFilter do
  @moduledoc """
  An attempt to reduce the volume of events sent to AppSignal in order to keep a lower bill.

  This sets the namespace to a well-known "ignore" value, which must be added to the
  AppSignal `ignore_namespaces` config value.

  See: https://github.com/etalab/transport-site/issues/3274

  The plug must be activated low-enough in the pipeline, otherwise the "ignore" value
  won't be used and instead the middleware value will take precedence.

  See: https://github.com/appsignal/appsignal-elixir/issues/865
  """

  def init(options), do: options

  def call(%Plug.Conn{} = conn, _opts) do
    if function_exported?(Appsignal.Tracer, :root_span, 0) do
      if must_ignore?(conn) do
        Appsignal.Tracer.root_span() |> Appsignal.Span.set_namespace("ignore")
      end
    end

    conn
  end

  # this method allows us to filter programmatically as needed
  defp must_ignore?(%Plug.Conn{} = conn) do
    conn.host =~ ~r/proxy/i
  end
end
