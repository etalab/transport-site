#! /usr/bin/env mix run

# Count unique ID PDC:
#
# cat consolidation.csv | cut -d',' -f1 | sort | uniq | grep -v "Non concerné" | grep -v "id_pdc_itinerance" | wc -l

require Logger

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

  def create_consolidation! do
    # NOTE: this does not scale.
    # TODO: compute total byte size in memory and decide accordingly
    resources = Transport.IRVE.Extractor.resources()

    resources = Transport.IRVE.Extractor.download_and_parse_all(resources, nil, keep_the_body_around: true)

    # TODO: also append to a secondary file listing the resources
    resources
    |> Enum.reject(fn(r) -> r.dataset_organisation_name == "data.gouv.fr" end)
    |> Enum.map(fn resource ->
      result = extract_data_from_resource(resource)
      if resource.line_count > 50_000 do
        IO.inspect(resource, IEx.inspect_opts)
        System.halt()
      end
      if result.dataframe_loaded do
        IO.puts("dataframe:ok:#{"id_pdc_itinerance" in Explorer.DataFrame.names(result.dataframe)}:#{resource.line_count}")
      else
        IO.puts("dataframe:ko:#{resource.line_count}")
      end
      resource |> Map.merge(result)
    end)
  end
end

defmodule NumberDistribution do
  require Explorer.DataFrame

  def analyze(numbers) do
    df = Explorer.DataFrame.new(%{
      "number" => numbers
    })

    df
    |> Explorer.DataFrame.mutate(
      below_10: number < 10,
      between_11_100: number >= 11 and number <= 100,
      between_101_2500: number > 100 and number <= 2500,
      above_2500: number > 2500
    )
    |> Explorer.DataFrame.summarise(
      count_below_10: sum(below_10),
      count_11_100: sum(between_11_100),
      count_101_2500: sum(between_101_2500),
      count_above_2500: sum(above_2500)
    )
    |> Explorer.DataFrame.to_rows()
    |> hd()
  end
end

output = ICanHazConsolidation.create_consolidation!()
counts = output |> Enum.map(fn(x) -> x.line_count end)
NumberDistribution.analyze(counts) |> IO.inspect(IEx.inspect_opts)

# TODO: assert no duplicate first, so we can safely convert to maps!

# TODO: gérer les erreurs dans le flux
# TODO: générer deux fichiers
# TODO: importance de la traçabilité générale
# TODO: garder le code existant compatible (outils en place, utilisés)
