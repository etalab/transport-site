Mix.install([
  # for UUID generation
  {:ecto, "~> 3.8.2"},
  # parser and encoder
  {:saxy, "~> 1.4"}
])
Code.require_file(__DIR__ |> (Path.join "/siri_queries.exs"))

timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
message_id = "Test::Message::#{Ecto.UUID.generate()}"
requestor_ref = "MY-REF"

request = SIRI.stop_points_discovery(timestamp, requestor_ref, message_id)

{:ok, parsed_request} = Saxy.SimpleForm.parse_string(request, cdata_as_characters: false)
# TODO: add encoding
# TODO: verify input encoding (saxy only support UTF-8)
encoded_request = Saxy.encode!(parsed_request, version: "1.0", encoding: :utf8)

File.write!("input.xml", request)
File.write!("output.xml", encoded_request)
