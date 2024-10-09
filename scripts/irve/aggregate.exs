#! /usr/bin/env mix run

# Count unique ID PDC:
#
# cat consolidation.csv | cut -d',' -f1 | sort | uniq | grep -v "Non concerné" | grep -v "id_pdc_itinerance" | wc -l

require Logger

# TODO: use real CSV for output
# TODO: filter out anormaly large files (datagouv resources)
# TODO: count bogus files and make sure we can parse them
# TODO: do not attempt to go web for now.

defmodule ICanHazConsolidation do

  # return a map with
  # - `dataframe` - if loaded successfully
  # - `dataframe_loaded` (true / false) - explicit status
  # - `raw_body` - kept around for later analysis (especially in case of failure)
  # - `http_status` - for reporting
  def extract_data_from_resource(resource) do
    Logger.info "Processing resource_id=#{resource.resource_id}"
    %{raw_body: body, status: status} = resource

    %{
      raw_body: body,
      http_status: status
    } |> Map.merge(try do
      df = Explorer.DataFrame.load_csv!(body)
      %{
        dataframe: df,
        dataframe_loaded: true
      }
    rescue
      error ->
        %{
          dataframe: nil,
          dataframe_loaded: false,
          dataframe_error: error
        }
    end)
  end

  def create_consolidation!() do
    # NOTE: this does not scale.
    # TODO: compute total byte size in memory and decide accordingly
    resources = Transport.IRVE.Extractor.resources() |> Enum.take(20)

    resources = Transport.IRVE.Extractor.download_and_parse_all(resources, nil, keep_the_body_around: true)

    # TODO: also append to a secondary file listing the resources
    resources
    |> Enum.each(fn resource ->
      result = extract_data_from_resource(resource)
      IO.inspect(result.dataframe[:id_pdc_itinerance], IEx.inspect_opts)
    end)
  end
end

ICanHazConsolidation.create_consolidation!()

# TODO: assert no duplicate first, so we can safely convert to maps!

# TODO: gérer les erreurs dans le flux
# TODO: générer deux fichiers
# TODO: importance de la traçabilité générale
# TODO: garder le code existant compatible (outils en place, utilisés)
