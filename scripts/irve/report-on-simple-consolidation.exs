require Explorer.DataFrame, as: DF

report_df =
  Path.join(__DIR__, "../../consolidation_transport_avec_doublons_irve_statique_rapport.csv")
  |> DF.from_csv!()

# general report
report_df
|> DF.mutate(error_message_trunc: re_replace(error_message, "\n.*", ""))
|> DF.mutate(error_message_trunc: substring(error_message_trunc, 0, 70))
|> DF.mutate(error_type_trunc: substring(error_type, 0, 18))
|> DF.group_by([:status, :error_type_trunc, :error_message_trunc])
|> DF.summarise(est_pdc_count: sum(estimated_pdc_count))
|> DF.sort_by(desc: est_pdc_count)
|> DF.print(limit: :infinity)

# report for files considered as invalid
report_df
|> DF.filter(status == "not_compliant_with_schema")
|> DF.select([:dataset_id, :resource_id, :dataset_title, :estimated_pdc_count, :status])
|> DF.sort_by(desc: estimated_pdc_count)
|> DF.print(limit: 20)
