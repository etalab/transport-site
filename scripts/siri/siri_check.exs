# NOTE: Elixir 1.13+ supports :config for `Mix.install/2` here instead
Application.put_env(:phoenix, :json_library, Jason)

Mix.install([
  {:req, "~> 0.2.1"},
  # for XML templating trick!
  {:phoenix_live_view, "~> 0.17.5"},
  # for UUID generation
  {:ecto, "~> 3.7.1"},
])

{args, _rest} = OptionParser.parse!(System.argv, strict: [endpoint: :string, requestor_ref: :string])

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
endpoint = (args |> Keyword.get(:endpoint)) || Helper.halt("Please provide --endpoint switch")
requestor_ref = (args |> Keyword.get(:requestor_ref)) || Helper.halt("Please provide --requestor-ref switch")

message_id = "Test::Message::#{Ecto.UUID.generate()}"

query = SIRI.check_status(timestamp, requestor_ref, message_id)

%{body: body, status: 200} = Req.post!(endpoint, query)

IO.inspect body
