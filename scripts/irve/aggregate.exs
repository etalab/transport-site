#! /usr/bin/env mix run

require Logger

defmodule ICanHazConsolidation do
  def create_consolidation!() do
    File.rm("consolidation.csv")
    {:ok, file} = File.open("consolidation.csv", [:write, :exclusive, :utf8])

    # NOTE: this does not scale.
    # TODO: compute total byte size in memory and decide accordingly
    resources = Transport.IRVE.Extractor.resources()

    resources = Transport.IRVE.Extractor.download_and_parse_all(resources, nil, keep_the_body_around: true)

    IO.write(file, "id_pdc_itinerance,resource_id\n")

    # TODO: also append to a secondary file listing the resources
    resources
    |> Enum.each(fn resource ->
      %{raw_body: body} = resource
      [headers | rows] = NimbleCSV.RFC4180.parse_string(body, skip_headers: false)

      rows
      |> Stream.map(fn r -> Enum.zip(headers, r) |> Map.new() end)
      |> Stream.each(fn r ->
        r = Map.take(r, ["id_pdc_itinerance"])
        IO.write(file, r["id_pdc_itinerance"] <> "," <> resource[:resource_id] <> "\n")
      end)
      |> Stream.run()
    end)

    :ok = File.close(file)
  end
end

ICanHazConsolidation.create_consolidation!()

IO.puts(File.read!("consolidation.csv"))
IO.puts("done")

# TODO: assert no duplicate first, so we can safely convert to maps!

# TODO: gérer les erreurs dans le flux
# TODO: générer deux fichiers
# TODO: importance de la traçabilité générale
# TODO: garder le code existant compatible (outils en place, utilisés)
