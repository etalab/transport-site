# NOTE: Elixir 1.13+ supports :config for `Mix.install/2` here instead
Application.put_env(:phoenix, :json_library, Jason)

Mix.install([
  {:req, "~> 0.2.1"},
  # for XML templating trick!
  {:phoenix_live_view, "~> 0.17.5"},
  # for UUID generation
  {:ecto, "~> 3.7.1"},
  # YAML config to make group tests easier (see https://github.com/etalab/transport_deploy/issues/49)
  {:yaml_elixir, "~> 2.8"},
  # a quick hack to pretty print XML (although it will change things a bit) during debugging
  # see https://elixirforum.com/t/what-is-your-best-trick-to-pretty-print-a-xml-string-with-elixir-or-erlang/42010
  {:floki, "~> 0.32.0"}
])

{args, _rest} = OptionParser.parse!(System.argv(), strict: [
  endpoint: :string,
  requestor_ref: :string,
  target: :string,
  pretty_dump: :boolean
  ])

defmodule Helper do
  def halt(error) do
    Mix.Shell.IO.error(error)
    System.halt(:abort)
  end
end

defmodule SIRI do
  def check_status(timestamp, requestor_ref, message_identifier) do
    # NOTE: we'll need to properly escape & encode the dynamic parts to avoid injection issues (à la XSS).
    """
    <?xml version="1.0" encoding="UTF-8"?>
    <S:Envelope xmlns:S="http://schemas.xmlsoap.org/soap/envelope/" xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/">
    <S:Body>
        <sw:CheckStatus xmlns:sw="http://wsdl.siri.org.uk" xmlns:siri="http://www.siri.org.uk/siri">
            <Request>
                <siri:RequestTimestamp>#{timestamp}</siri:RequestTimestamp>
                <siri:RequestorRef>#{requestor_ref}</siri:RequestorRef>
                <siri:MessageIdentifier>#{message_identifier}</siri:MessageIdentifier>
            </Request>
            <RequestExtension/>
        </sw:CheckStatus>
    </S:Body>
    </S:Envelope>
    """
  end
end

timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

target = args |> Keyword.get(:target)

{endpoint, requestor_ref} =
  if target do
    config = File.read!("#{__DIR__}/config.yml") |> YamlElixir.read_from_string!()
    config = config |> Map.fetch!("feeds") |> Enum.filter(&(&1["identifier"] == target))
    [%{"requestor_ref" => requestor_ref, "target_url" => target_url}] = config
    {target_url, requestor_ref}
  else
    endpoint =
      args |> Keyword.get(:endpoint) || Helper.halt("Please provide --endpoint switch (or --target & config.yml)")

    requestor_ref =
      args |> Keyword.get(:requestor_ref) ||
        Helper.halt("Please provide --requestor-ref switch (or --target & config.yml)")

    {endpoint, requestor_ref}
  end

message_id = "Test::Message::#{Ecto.UUID.generate()}"

query = SIRI.check_status(timestamp, requestor_ref, message_id)

%{body: body, status: 200} = Req.post!(endpoint, query)

if args[:pretty_dump] do
  IO.puts body
  |> Floki.parse_document!()
  |> Floki.raw_html(pretty: true)
end
