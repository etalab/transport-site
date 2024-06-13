#! /usr/bin/env mix run

# Start adding up everything we have, pre-consolidation, unfiltered, so that
# we can have solid discussions about the content, the validation of each file,
# the ids, and who should win when duplicates arise.

require Logger

Transport.IRVE.Extractor.resources()
|> Stream.each(&IO.inspect(&1, IEx.inspect_opts))
|> Stream.run()
