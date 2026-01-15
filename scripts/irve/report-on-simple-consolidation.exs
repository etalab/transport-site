require Explorer.DataFrame, as: DF

report_df =
  Path.join(__DIR__, "../../irve_static_consolidation_v2_report.csv")
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
