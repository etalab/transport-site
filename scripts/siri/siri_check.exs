Mix.install([
  {:req, "~> 0.2.1"},
  # for UUID generation
  {:ecto, "~> 3.7.1"},
  # YAML config to make group tests easier (see https://github.com/etalab/transport_deploy/issues/49)
  {:yaml_elixir, "~> 2.8"}
])

Code.require_file("siri_queries.exs")

{args, _rest} =
  OptionParser.parse!(System.argv(),
    strict: [
      endpoint: :string,
      requestor_ref: :string,
      target: :string,
      request: :string,
      line_refs: :string,
      dump_query: :boolean,
      dump_response: :boolean,
      stop_ref: :string
    ]
  )

defmodule Helper do
  def halt(error) do
    Mix.Shell.IO.error(error)
    System.halt(:abort)
  end
end

# must conform to https://www.w3.org/TR/xmlschema-2/#dateTime
timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

target = args |> Keyword.get(:target)

request =
  args |> Keyword.get(:request) ||
    Helper.halt(
      "Please provide --request switch (check_status, lines_discovery, stop_points_discovery, get_estimated_timetable, get_stop_monitoring, get_general_message)"
    )

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

# NOTE: a more dynamic dispatching will be easy to add later, at this point I'm
# more interested in having actual queries available quickly.
query =
  case request do
    "check_status" ->
      SIRI.check_status(timestamp, requestor_ref, message_id)

    "lines_discovery" ->
      SIRI.lines_discovery(timestamp, requestor_ref, message_id)

    "stop_points_discovery" ->
      SIRI.stop_points_discovery(timestamp, requestor_ref, message_id)

    "get_estimated_timetable" ->
      line_refs =
        (args[:line_refs] || Helper.halt("Please provide --line-refs switch (comma-separated)")) |> String.split(",")

      SIRI.get_estimated_timetable(timestamp, requestor_ref, message_id, line_refs)

    "get_stop_monitoring" ->
      stop_ref = args[:stop_ref] || Helper.halt("Please provide --stop-ref switch")
      SIRI.get_stop_monitoring(timestamp, requestor_ref, message_id, stop_ref)

    "get_general_message" ->
      SIRI.get_general_message(timestamp, requestor_ref, message_id)
  end

if args[:dump_query] do
  IO.puts(query)
end

# TODO: fix `--target carene` (currently returning https://developer.mozilla.org/fr/docs/Web/HTTP/Status/415)
# We probably need to pass a proper HTTP header.
%{body: body, status: 200} = Req.post!(endpoint, query)

if args[:dump_response] do
  IO.puts(body)
else
  IO.puts("Got 200. Add --dump-response to see the actual response. Pipe into \"| xmllint --format -\" for indentation")
end

# NOTE: we'll parse the document (XPath) on siri:status & siri:dataready (after verifying profile) later to provide
# a better test.
# One must be careful with memory consumption when doing such tasks, I have benchmarked various options.
