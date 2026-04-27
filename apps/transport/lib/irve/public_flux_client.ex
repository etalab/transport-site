defmodule Transport.IRVE.PublicFluxClient do
  @moduledoc """
  Consume public IRVE consolidated fluxes via the public proxy URLs.

  Acts as a faithful "reuser" pattern — it goes through the same public
  endpoints an external consumer would use, with a small Cachex layer to
  avoid hammering the proxy when several sessions are open.
  """

  @static_dedup_url "https://proxy.transport.data.gouv.fr/resource/consolidation-transport-irve-statique"
  @static_with_doublons_url "https://proxy.transport.data.gouv.fr/resource/consolidation-transport-avec-doublons-irve-statique"
  @dynamic_url "https://proxy.transport.data.gouv.fr/resource/consolidation-nationale-irve-dynamique?include_origin=1"

  @static_ttl :timer.hours(1)
  @dynamic_ttl :timer.seconds(5)

  @type flavour :: :dedup | :with_doublons

  @spec fetch_static(flavour()) :: Explorer.DataFrame.t()
  def fetch_static(:dedup), do: cached("irve:public:static:dedup", @static_dedup_url, @static_ttl)

  def fetch_static(:with_doublons),
    do: cached("irve:public:static:with_doublons", @static_with_doublons_url, @static_ttl)

  @spec fetch_dynamic() :: Explorer.DataFrame.t()
  def fetch_dynamic, do: cached("irve:public:dynamic", @dynamic_url, @dynamic_ttl)

  defp cached(key, url, ttl) do
    Transport.Cache.fetch(key, fn -> fetch_csv(url) end, ttl)
  end

  defp fetch_csv(url) do
    %Req.Response{status: 200, body: body} =
      Transport.Req.impl().get!(url, redirect_log_level: false, decode_body: false)

    Explorer.DataFrame.load_csv!(body, infer_schema_length: 0)
  end
end
