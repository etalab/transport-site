# Health-check every SIRI feed of a transport.data.gouv.fr dataset:
# send SIRI CheckStatus to each `original_url`, report HTTP code + <Status>.
# Sequential, honors 429 Retry-After. Defaults to the Aix-Marseille-Provence dataset.
#
# Usage: elixir scripts/siri_check.exs [--dataset <slug-or-id>] [--api-base <url>]

Mix.install([{:req, "~> 0.5"}, {:sweet_xml, "~> 0.7"}])

defmodule SiriCheck do
  import SweetXml
  @max_attempts 8

  # `local-name()` ignores the various ns prefixes SIRI producers use.
  def status(body), do: xpath(body, ~x"//*[local-name()='Status']/text()"s)
  def error_text(body), do: xpath(body, ~x"//*[local-name()='ErrorText']/text()"s)

  def envelope(ref) do
    ts = DateTime.utc_now() |> DateTime.to_iso8601()
    mid = "Test::Message::" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))

    ~s|<?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/"><S:Body>
    <sw:CheckStatus xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
    <Request><siri:RequestTimestamp>#{ts}</siri:RequestTimestamp><siri:RequestorRef>#{ref}</siri:RequestorRef><siri:MessageIdentifier>#{mid}</siri:MessageIdentifier></Request>
    <RequestExtension/></sw:CheckStatus></S:Body></S:Envelope>|
  end

  def post(url, ref, attempt \\ 0, counts \\ %{rate_limit: 0, error: 0}) do
    case attempt_post(url, ref) do
      {:ok, %{status: 429} = resp, _} when attempt < @max_attempts ->
        retry(url, ref, attempt, retry_after_ms(resp) || backoff(attempt), bump(counts, :rate_limit))

      {:ok, %{status: 429} = resp, elapsed} ->
        {:ok, resp, bump(counts, :rate_limit), elapsed}

      {:ok, resp, elapsed} ->
        {:ok, resp, counts, elapsed}

      {:error, _msg} when attempt < @max_attempts ->
        retry(url, ref, attempt, backoff(attempt), bump(counts, :error))

      {:error, msg} ->
        {:error, msg, bump(counts, :error)}
    end
  end

  defp retry(url, ref, attempt, wait, counts) do
    Process.sleep(wait)
    post(url, ref, attempt + 1, counts)
  end

  defp bump(counts, key), do: Map.update!(counts, key, &(&1 + 1))

  def counts_suffix(%{rate_limit: r, error: e}) do
    parts =
      [{r, "429"}, {e, "err"}]
      |> Enum.filter(fn {n, _} -> n > 0 end)
      |> Enum.map_join(" ", fn {n, l} -> "#{n}×#{l}" end)

    if parts == "", do: "", else: " (#{parts})"
  end

  defp attempt_post(url, ref) do
    t0 = System.monotonic_time(:millisecond)
    resp = Req.post!(url, body: envelope(ref), headers: [{"content-type", "text/xml"}], receive_timeout: 30_000)
    {:ok, resp, System.monotonic_time(:millisecond) - t0}
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp backoff(attempt), do: min(trunc(:math.pow(2, attempt) * 1_000), 60_000)

  defp retry_after_ms(resp) do
    with [v | _] <- resp.headers["retry-after"], {n, ""} <- Integer.parse(v), do: min(n * 1_000, 60_000)
  end
end

{opts, _} = OptionParser.parse!(System.argv(), strict: [dataset: :string, api_base: :string])
api_base = opts[:api_base] || "https://transport.data.gouv.fr"
dataset_id = opts[:dataset] || "5b3b3de988ee38708ada1789"

dataset = Req.get!("#{api_base}/api/datasets/#{dataset_id}").body

dataset["resources"]
|> Enum.filter(&(&1["format"] == "SIRI"))
|> Enum.with_index(1)
|> Enum.each(fn {r, i} ->
  ref = r["requestor_ref"]
  url = r["original_url"]

  {color, line} =
    if is_nil(ref) do
      {:red, "missing requestor_ref"}
    else
      case SiriCheck.post(url, ref) do
        {:ok, resp, counts, elapsed} ->
          siri = SiriCheck.status(resp.body)
          err = SiriCheck.error_text(resp.body)
          color = if resp.status == 200 and siri == "true", do: :green, else: :red
          err_part = if err != "", do: " — #{err}", else: ""
          time_part = " #{Float.round(elapsed / 1000, 1)}s"
          {color, "HTTP #{resp.status} Status=#{siri}#{time_part}#{SiriCheck.counts_suffix(counts)}#{err_part}"}

        {:error, msg, counts} ->
          {:red, "error: #{msg}#{SiriCheck.counts_suffix(counts)}"}
      end
    end

  IO.puts(IO.ANSI.format([color, "[#{i}] #{line}", :reset, " — #{r["title"]}\n     #{url}"]))
end)
