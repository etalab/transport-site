# mix run --no-start scripts/irve/afirev.exs [source]
#
# Cross-checks the operator prefixes of an IRVE static consolidation (`FRxxx`, start of `id_pdc_itinerance`) against
# the AFIREV registry: active operators missing from the consolidation (`ACTIVE`, and `AWAITING_PAYMENT` which also
# covers renewals), prefixes used but not registered, and prefixes used while not active.
#
# source: see compare.exs (default: transport).
# Registry: https://api.afirev.fr/public/prefixes, the undocumented JSON loaded by the directory iframe of
# https://afirev.fr/prefixes/consulter-l-annuaire/ (the data.gouv dataset 6564aa9a57ba1db0c3ad5cba only links to
# that page). Only `CHARGE` and `BOTH` prefixes are kept (`MOBILITY` ones identify service providers, not stations).

Code.require_file("support/sources.exs", __DIR__)

defmodule Afirev do
  require Explorer.DataFrame, as: DF
  alias IRVEScripts.Sources

  @registry_url "https://api.afirev.fr/public/prefixes"
  @columns ["id_pdc_itinerance", "datagouv_resource_id", "nom_operateur", "nom_amenageur"]

  def run(argv) do
    source = List.first(argv) || "transport"
    registry = load_registry()
    df = source |> Sources.resolve() |> Sources.load(@columns)
    used = used_prefixes(df)

    print_overview(registry, df, used)

    absent = registry |> Map.drop(Map.keys(used)) |> Map.values()
    {listed, others} = Enum.split_with(absent, &(&1["status"] in ["ACTIVE", "AWAITING_PAYMENT"]))
    IO.puts("\n== #{length(listed)} ACTIVE or AWAITING_PAYMENT registry prefixes absent from #{source} ==")
    IO.puts("(also absent: #{others |> Enum.frequencies_by(& &1["status"]) |> inspect()})")

    listed
    |> Enum.sort_by(&{&1["status"], &1["prefixId"]})
    |> print_rows(["prefixId", "status", "amenageurName", "exploitantName", "name"])

    unregistered = used |> Map.drop(Map.keys(registry)) |> Map.values() |> Enum.sort_by(& &1["pdc"], :desc)
    IO.puts("\n== #{length(unregistered)} prefixes used in #{source} but not in the registry ==")
    print_rows(unregistered, ["prefix", "pdc", "resources", "nom_operateur", "nom_amenageur"])

    not_active =
      used
      |> Map.take(Map.keys(registry))
      |> Map.values()
      |> Enum.map(&Map.merge(&1, Map.take(registry[&1["prefix"]], ["status", "exploitantName"])))
      |> Enum.reject(&(&1["status"] == "ACTIVE"))
      |> Enum.sort_by(& &1["pdc"], :desc)

    IO.puts("\n== #{length(not_active)} prefixes used in #{source} while not ACTIVE in the registry ==")
    print_rows(not_active, ["prefix", "status", "pdc", "resources", "exploitantName", "nom_operateur"])
  end

  defp load_registry do
    Sources.cached_download!("afirev", @registry_url, "json")
    |> File.read!()
    |> Jason.decode!()
    |> Map.fetch!("data")
    |> Enum.filter(&(&1["type"] in ["CHARGE", "BOTH"]))
    |> Map.new(&{&1["prefixId"], &1})
  end

  # FR prefix → distinct PDCs, resources and a sample of operator / aménageur names
  defp used_prefixes(df) do
    df
    |> DF.filter(prefix_bucket == "FR")
    |> DF.group_by("prefix")
    |> DF.summarise(
      pdc: n_distinct(id_pdc_itinerance),
      resources: n_distinct(datagouv_resource_id),
      nom_operateur: first(nom_operateur),
      nom_amenageur: first(nom_amenageur)
    )
    |> DF.to_rows()
    |> Map.new(&{&1["prefix"], &1})
  end

  defp print_overview(registry, df, used) do
    statuses = registry |> Map.values() |> Enum.frequencies_by(& &1["status"])
    IO.puts("Registry (CHARGE/BOTH): #{map_size(registry)} prefixes #{inspect(statuses)}")
    buckets = df["prefix_bucket"] |> Explorer.Series.to_list() |> Enum.frequencies()
    IO.puts("Source rows by id_pdc_itinerance prefix: #{inspect(buckets)}")
    IO.puts("Distinct FR prefixes used: #{map_size(used)}, #{map_size(Map.take(used, Map.keys(registry)))} registered")
  end

  defp print_rows([], _columns), do: :ok
  defp print_rows(rows, columns), do: rows |> DF.new() |> DF.select(columns) |> DF.print(limit: :infinity)
end

Afirev.run(System.argv())
