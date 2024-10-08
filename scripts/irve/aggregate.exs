#! /usr/bin/env mix run

# Count unique ID PDC:
#
# cat consolidation.csv | cut -d',' -f1 | sort | uniq | grep -v "Non concerné" | grep -v "id_pdc_itinerance" | wc -l

require Logger

defmodule ICanHazConsolidation do

  def process_resource(resource, file) do
    try do
      Logger.info "Processing resource_id=#{resource.resource_id}"
      %{raw_body: body, status: status} = resource
      [headers | rows] = NimbleCSV.RFC4180.parse_string(body, skip_headers: false)

      if status != 200 do
        raise "Whoopsy - got HTTP status #{status}, expected 200"
      end

      rows
      |> Stream.map(fn r -> Enum.zip(headers, r) |> Map.new() end)
      |> Stream.each(fn r ->
        r = Map.take(r, ["id_pdc_itinerance", "coordonneesXY"])
        IO.write(file, r["id_pdc_itinerance"] <> "," <> r["coordonneesXY"] <> "," <> resource[:resource_id] <> "\n")
      end)
      |> Stream.run()
    rescue
      error -> IO.puts "an error occurred (#{error |> inspect})"
    end
end

  def create_consolidation!() do
    File.rm("consolidation.csv")
    {:ok, file} = File.open("consolidation.csv", [:write, :exclusive, :utf8])

    # NOTE: this does not scale.
    # TODO: compute total byte size in memory and decide accordingly
    resources = Transport.IRVE.Extractor.resources()

    resources = Transport.IRVE.Extractor.download_and_parse_all(resources, nil, keep_the_body_around: true)

    IO.write(file, "id_pdc_itinerance,coordonneesXY,resource_id\n")

    # TODO: also append to a secondary file listing the resources
    resources
    |> Enum.each(fn resource ->
      process_resource(resource, file)
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
