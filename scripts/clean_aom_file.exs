# Run with `mix run scripts/clean_aom_file.exs`
aom_communes_filepath = "base-rt-2023-liste-communes-vdegove.csv"
aom_filepath = "base-rt-2023-liste-aom-vdegove.csv"

aom_communes_list = aom_communes_filepath
|> File.stream!()
|> CSV.decode!(headers: true)
|> Enum.to_list()

aom_communes_map_by_siren_aom = aom_communes_list
|> Enum.group_by(& &1["N° SIREN AOM"])

aom_communes_map_by_siren_groupement = aom_communes_list
|> Enum.group_by(& &1["N° SIREN groupement"])

aom_filepath
|> File.stream!()
|> CSV.decode!(headers: true)
|> Enum.each(fn row ->
  siren_aom = row["N° SIREN"]
  # CEREMA made a mistake, sometimes the SIREN in AOM list refers to the SIREN of groupement
  communes_list_for_aom = aom_communes_map_by_siren_aom[siren_aom] || aom_communes_map_by_siren_groupement[siren_aom]
  if communes_list_for_aom == nil, do: IO.puts"no communes for #{siren_aom}"
  if String.to_integer(row["Nombre de communes du RT"]) != Enum.count(communes_list_for_aom), do:
    IO.puts("mismatch of number of communes for #{siren_aom} #{row["Nom de l’AOM"]}, AOM : #{Enum.count(communes_list_for_aom)}, RT : #{row["Nombre de communes du RT"]}")
end)
